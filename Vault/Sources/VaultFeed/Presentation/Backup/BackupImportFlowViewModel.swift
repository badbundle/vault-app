import Foundation
import FoundationExtensions
import PDFKit
import VaultBackup
import VaultCore
import VaultKeygen

@MainActor
@Observable
public final class BackupImportFlowViewModel {
    public enum PayloadState: Equatable {
        case none
        case needsPasswordEntry(EncryptedVault)
        case error(PresentationError)
        /// We need the UUID so each `ready` state is unique in terms of equality.
        case ready(VaultApplicationPayload, UUID)

        var isError: Bool {
            switch self {
            case .error: true
            case .none, .ready, .needsPasswordEntry: false
            }
        }
    }

    public enum ImportState: Equatable {
        case notStarted
        case error(PresentationError)
        case success

        public var isFinished: Bool {
            switch self {
            case .success: true
            default: false
            }
        }
    }

    public private(set) var importState: ImportState = .notStarted

    public private(set) var payloadState: PayloadState = .none
    public private(set) var isImporting: Bool = false
    public let importContext: BackupImportContext

    private let dataModel: VaultDataModel
    /// The backup password the user already has on their device.
    /// If the imported backup was encrypted with this same password, we don't need to prompt the user.
    private let existingBackupPassword: DerivedEncryptionKey?
    private let encryptedVaultDecoder: any EncryptedVaultDecoder<KeyData<32>>
    private let backupPDFDetatcher: any VaultBackupPDFDetatcher
    private var importPDFTask: Task<Void, any Error>?

    public init(
        importContext: BackupImportContext,
        dataModel: VaultDataModel,
        existingBackupPassword: DerivedEncryptionKey?,
        encryptedVaultDecoder: any EncryptedVaultDecoder<KeyData<32>>,
        backupPDFDetatcher: any VaultBackupPDFDetatcher = VaultBackupPDFDetatcherImpl(),
    ) {
        self.importContext = importContext
        self.dataModel = dataModel
        self.existingBackupPassword = existingBackupPassword
        self.encryptedVaultDecoder = encryptedVaultDecoder
        self.backupPDFDetatcher = backupPDFDetatcher
    }

    public func handleImport(fromPDF pdfDataResult: Result<Data, any Error>) async {
        importState = .notStarted
        await performImport {
            let data = pdfDataResult.mapError { error in
                PresentationError(
                    userTitle: "File Error",
                    userDescription: "There was an error with the file you selected. Please try again.",
                    debugDescription: error.localizedDescription,
                )
            }
            let pdfData = try data.get()
            guard let pdf = PDFDocument(data: pdfData) else { throw InvalidURLError() }
            return try backupPDFDetatcher.detachEncryptedVault(fromPDF: pdf)
        }
    }

    public func handleImport(fromEncryptedVault encryptedVault: EncryptedVault) async {
        importState = .notStarted
        await performImport {
            encryptedVault
        }
    }

    private func performImport(getEncryptedVault: () throws -> EncryptedVault) async {
        do {
            isImporting = true
            defer { isImporting = false }

            let encryptedVault = try getEncryptedVault()
            let flowState = BackupImportFlowState(
                encryptedVault: encryptedVault,
                encryptedVaultDecoder: encryptedVaultDecoder,
            )
            let action = flowState.passwordProvided(password: existingBackupPassword)
            switch action {
            case .promptForDifferentPassword:
                payloadState = .needsPasswordEntry(encryptedVault)
            case let .backupDataError(error):
                throw error
            case let .readyToImport(applicationPayload):
                payloadState = .ready(applicationPayload, UUID())
            }
        } catch let error as any LocalizedError {
            payloadState = .error(.init(localizedError: error))
        } catch {
            payloadState = .error(PresentationError(
                userTitle: "Document Error",
                userDescription: "There was an error with the this Vault export document. Please check the document, your internet, and try again.",
                debugDescription: error.localizedDescription,
            ))
        }
    }

    struct InvalidURLError: Error {}
    enum PasswordError: Error, LocalizedError {
        case noPassword

        var errorDescription: String? {
            switch self {
            case .noPassword: "No password"
            }
        }
    }

    public func handleVaultDecoded(payload: VaultApplicationPayload) {
        payloadState = .ready(payload, UUID())
    }

    /// Clears the pending password prompt when the user abandons it.
    ///
    /// `PayloadState` is `Equatable`, so leaving the state at `.needsPasswordEntry` would make a
    /// second import of the same document compare equal to the first and produce no change for the
    /// UI to react to — the prompt could never be re-presented. Resetting on cancel keeps that
    /// transition observable.
    ///
    /// Guarded so a dismissal that follows a successful decode cannot clobber the `.ready` payload.
    public func cancelPasswordEntry() {
        guard case .needsPasswordEntry = payloadState else { return }
        payloadState = .none
    }

    public func importPayload(payload: VaultApplicationPayload) async {
        do {
            switch importContext {
            case .toEmptyVault, .merge:
                try await dataModel.importMerge(payload: payload)
            case .override:
                try await dataModel.importOverride(payload: payload)
            }
            importState = .success
        } catch let error as any LocalizedError {
            importState = .error(.init(localizedError: error))
        } catch {
            importState = .error(PresentationError(
                userTitle: "Import Error",
                userDescription: "There was an error importing the data to your vault. Please try again.",
                debugDescription: error.localizedDescription,
            ))
        }
    }
}
