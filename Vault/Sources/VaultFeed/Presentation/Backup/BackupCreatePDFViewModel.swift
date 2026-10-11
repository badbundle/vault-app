import Combine
import Foundation
import FoundationExtensions
import PDFKit
import VaultBackup
import VaultCore
import VaultExport
import VaultKeygen

@MainActor
@Observable
public final class BackupCreatePDFViewModel {
    public enum State: Equatable {
        case idle
        case loading
        case error(PresentationError)
        case success

        public var isError: Bool {
            switch self {
            case .error: true
            default: false
            }
        }
    }

    public enum Size: Equatable, IdentifiableSelf, CaseIterable, Codable, Sendable {
        case a2
        case a3
        case a4
        case a5
        case usLetter
        case usLegal
        case usTabloid
        case usLedger

        public var localizedTitle: String {
            switch self {
            case .a2: "A2"
            case .a3: "A3"
            case .a4: "A4"
            case .a5: "A5"
            case .usLetter: "US Letter"
            case .usLegal: "US Legal"
            case .usTabloid: "US Tabloid"
            case .usLedger: "US Ledger"
            }
        }

        fileprivate var documentSize: any PDFDocumentSize {
            switch self {
            case .a2: A2DocumentSize()
            case .a3: A3DocumentSize()
            case .a4: A4DocumentSize()
            case .a5: A5DocumentSize()
            case .usLetter: USLetterDocumentSize()
            case .usLegal: USLegalDocumentSize()
            case .usTabloid: USTabloidDocumentSize()
            case .usLedger: USLedgerDocumentSize()
            }
        }

        public var aspectRatio: Double {
            documentSize.aspectRatio
        }
    }

    /// Exported PDF document that has been generated.
    ///
    /// It's only in memory until the user saves it somewhere, so it isn't a backup yet. It's written to a file
    /// just while the share sheet has it (`BackupPDFTemporaryFiles`).
    public struct GeneratedPDF: Equatable, Hashable {
        public let document: PDFDocument
        public let size: Size
        public let dataHash: Digest<VaultApplicationPayload>.SHA256
        /// When the vault was exported into this PDF.
        public let createdDate: Date
        /// The vault exported into this PDF (`BackupEventLogger.vaultToken`), which saving it is logged into.
        public let vaultToken: Int

        public init(
            document: PDFDocument,
            size: Size,
            dataHash: Digest<VaultApplicationPayload>.SHA256,
            createdDate: Date,
            vaultToken: Int,
        ) {
            self.document = document
            self.size = size
            self.dataHash = dataHash
            self.createdDate = createdDate
            self.vaultToken = vaultToken
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.dataHash == rhs.dataHash
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(dataHash)
        }
    }

    private static let pdfSizeKey = Key<Size>(VaultIdentifiers.Preferences.PDF.defaultSize)
    /// The text the hint used to start with. The hint is printed in plain text, so it now starts empty (VAULT-63).
    /// Making a PDF saves the hint, so a vault that made one without changing this has it saved: it's shown as no
    /// hint.
    private static let formerDefaultUserHint =
        "This is my description, which is visible in plain text on the vault backup. You can use the Vault app to import this data if you lose access to your device."

    public private(set) var state: State = .idle
    public var size: Size = .a4
    public var authorName: String = "Vault"
    public var userHint: String = ""
    public var userDescriptionEncrypted: String = "You can use the Vault app to import this backup."
    private let generatedPDFSubject = PassthroughSubject<GeneratedPDF, Never>()

    private let backupPassword: DerivedEncryptionKey
    private let dataModel: VaultDataModel
    private let clock: any EpochClock
    private let defaults: Defaults
    private let hintStorage: any BackupPDFHintStorage
    /// The vault open when the page opened, whose hint it shows and saves, and which a PDF is logged into.
    private let vaultToken: Int

    /// - Parameters:
    ///   - defaults: Where the paper size is kept, device-wide.
    ///   - hintStorage: Where the hint is kept: the open vault's own settings (`OpenVaultBackupSettings`), so no
    ///     vault shows or prints another's.
    public init(
        backupPassword: DerivedEncryptionKey,
        dataModel: VaultDataModel,
        clock: any EpochClock,
        defaults: Defaults,
        hintStorage: any BackupPDFHintStorage,
    ) {
        self.backupPassword = backupPassword
        self.dataModel = dataModel
        self.clock = clock
        self.defaults = defaults
        self.hintStorage = hintStorage
        vaultToken = hintStorage.vaultToken

        size = defaults.get(for: Self.pdfSizeKey) ?? .a4
        let savedHint = hintStorage.pdfUserHint()
        userHint = savedHint == Self.formerDefaultUserHint ? "" : savedHint ?? ""
    }

    /// Publishes a PDF whenever one is generated.
    public func generatedPDFPublisher() -> some Publisher<GeneratedPDF, Never> {
        generatedPDFSubject
    }

    public func createPDF() async {
        do {
            let currentDate = clock.currentDate
            state = .loading
            let payload = try await dataModel.makeExport(userDescription: userDescriptionEncrypted)
            let size = size
            let rendered = try await makeBackupPDF(
                payload: payload,
                size: size,
                authorName: authorName,
                userHint: userHint,
            )
            generatedPDFSubject.send(.init(
                document: rendered.document,
                size: size,
                dataHash: rendered.hash,
                createdDate: currentDate,
                vaultToken: vaultToken,
            ))

            // The backup event is logged once the PDF is saved (see `BackupGeneratedPDFViewModel`), not
            // here: a PDF that's never saved isn't a backup.
            commitLatestSettings()
            state = .success
        } catch {
            state = .error(.init(
                userTitle: "PDF Error",
                userDescription: "Failed to create PDF. Please try again.",
                debugDescription: error.localizedDescription,
            ))
        }
    }

    private func commitLatestSettings() {
        try? defaults.set(size, for: Self.pdfSizeKey)
        // Dropped if another vault has opened since the page did: the hint is this vault's.
        try? hintStorage.savePDFUserHint(userHint, for: vaultToken)
    }
}

// MARK: - PDF Generation

extension BackupCreatePDFViewModel {
    /// Encrypts the vault and renders it to a PDF, off the main actor: rendering every QR code is slow, and would
    /// otherwise freeze the app until it's done.
    private nonisolated func makeBackupPDF(
        payload: VaultApplicationPayload,
        size: Size,
        authorName: String,
        userHint: String,
    ) async throws -> sending (document: PDFDocument, hash: Digest<VaultApplicationPayload>.SHA256) {
        let backupExporter = EncryptedVaultEncoder(clock: clock, backupPassword: backupPassword)
        let exportPayload = try VaultExportPayload(
            encryptedVault: backupExporter.encryptAndEncode(payload: payload),
            userDescription: userHint,
            created: clock.currentDate,
        )
        let pdfCreator = VaultBackupPDFGenerator(
            size: size.documentSize,
            documentTitle: "Backup",
            applicationName: "Vault",
            authorName: authorName,
        )
        let document = try pdfCreator.makePDF(payload: exportPayload)
        let hash = try DigestHasher().sha256(value: payload)
        return (document, hash)
    }
}
