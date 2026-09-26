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

        public init(
            document: PDFDocument,
            size: Size,
            dataHash: Digest<VaultApplicationPayload>.SHA256,
            createdDate: Date,
        ) {
            self.document = document
            self.size = size
            self.dataHash = dataHash
            self.createdDate = createdDate
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.dataHash == rhs.dataHash
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(dataHash)
        }
    }

    private static let pdfSizeKey = Key<Size>(VaultIdentifiers.Preferences.PDF.defaultSize)
    private static let userHintKey = Key<String>(VaultIdentifiers.Preferences.PDF.userHint)
    private static let defaultUserHint =
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

    public init(
        backupPassword: DerivedEncryptionKey,
        dataModel: VaultDataModel,
        clock: any EpochClock,
        defaults: Defaults,
    ) {
        self.backupPassword = backupPassword
        self.dataModel = dataModel
        self.clock = clock
        self.defaults = defaults

        size = defaults.get(for: Self.pdfSizeKey) ?? .a4
        userHint = defaults.get(for: Self.userHintKey) ?? Self.defaultUserHint
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
            let document = try await makeBackupPDFDocument(payload: payload)
            let hash = try DigestHasher().sha256(value: payload)
            generatedPDFSubject.send(.init(
                document: document,
                size: size,
                dataHash: hash,
                createdDate: currentDate,
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
        try? defaults.set(userHint, for: Self.userHintKey)
    }
}

// MARK: - PDF Generation

extension BackupCreatePDFViewModel {
    /// Exports and encrypts the full vault from storage, rendering to a PDF
    private func makeBackupPDFDocument(payload: VaultApplicationPayload) async throws -> PDFDocument {
        let pdfCreator = VaultBackupPDFGenerator(
            size: size.documentSize,
            documentTitle: "Backup",
            applicationName: "Vault",
            authorName: authorName,
        )
        let exportPayload = try await makeExportPayload(payload: payload)
        return try pdfCreator.makePDF(payload: exportPayload)
    }

    /// Encrypt on background thread.
    private nonisolated func makeExportPayload(payload: VaultApplicationPayload) async throws -> VaultExportPayload {
        let backupExporter = EncryptedVaultEncoder(clock: clock, backupPassword: backupPassword)
        let encryptedVault = try backupExporter.encryptAndEncode(payload: payload)
        return await VaultExportPayload(
            encryptedVault: encryptedVault,
            userDescription: userHint,
            created: clock.currentDate,
        )
    }
}
