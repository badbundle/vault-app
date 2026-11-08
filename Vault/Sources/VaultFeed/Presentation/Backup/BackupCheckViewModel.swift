import Foundation
import VaultBackup

/// Checks that a backup opens with its password, so it could be restored, without restoring it.
///
/// It reads the backup from its PDF, or from the QR codes the user scans. Then the password screen
/// (`BackupKeyDecryptorViewModel`) derives the key and decrypts and decodes the whole backup, exactly as it does
/// before a restore imports one, and the check passes once it has.
///
/// - It has no data model, so it can't change anything on the device: no item, setting or "Last backup".
/// - It's never given what the backup holds, so it can only say that the backup opened. Saying how many items there
///   were would count hidden items too, and tell someone making the user check a backup that there are hidden items
///   to find (MANIFESTO C5).
/// - It needs the backup's own password, as restoring does (G59), and no device authentication. It reads neither the
///   vault nor the backup key this device keeps, and a backup's file and password open it in Vault on any device.
@MainActor
@Observable
public final class BackupCheckViewModel {
    public enum State: Equatable {
        case none
        case needsPasswordEntry(EncryptedVault)
        case error(PresentationError)
        /// The backup opened with the password typed for it, and everything in it could be read.
        ///
        /// We need the UUID so checking the same backup again is a change the UI sees.
        case opened(UUID)

        public var isError: Bool {
            switch self {
            case .error: true
            case .none, .needsPasswordEntry, .opened: false
            }
        }

        public var isOpened: Bool {
            switch self {
            case .opened: true
            case .none, .needsPasswordEntry, .error: false
            }
        }
    }

    public private(set) var state: State = .none

    private let backupPDFDetatcher: any VaultBackupPDFDetatcher

    public init(backupPDFDetatcher: any VaultBackupPDFDetatcher = VaultBackupPDFDetatcherImpl()) {
        self.backupPDFDetatcher = backupPDFDetatcher
    }

    /// Reads the backup out of a PDF, a PDF backup or an auto-backup, then asks for its password.
    public func check(pdf pdfDataResult: Result<Data, any Error>) async {
        do {
            let encryptedVault = try await BackupPDFReader.encryptedVault(
                fromPDF: pdfDataResult,
                using: backupPDFDetatcher,
            )
            state = .needsPasswordEntry(encryptedVault)
        } catch {
            state = .error(BackupPDFReader.presentationError(for: error))
        }
    }

    /// Asks for the password of a backup read from its QR codes.
    public func check(encryptedVault: EncryptedVault) {
        state = .needsPasswordEntry(encryptedVault)
    }

    /// The password screen decrypted and decoded the backup. What it held isn't passed on, and nothing keeps it.
    ///
    /// Not guarded on the password prompt: closing the scanner's sheet as the password's opens can clear the prompt
    /// first, as `cancelPasswordEntry()`.
    public func backupDidOpen() {
        state = .opened(UUID())
    }

    /// Clears the pending password prompt when the user abandons it, so the same backup can be checked again.
    ///
    /// Guarded so a dismissal that follows the backup opening can't clear what the check found.
    public func cancelPasswordEntry() {
        guard case .needsPasswordEntry = state else { return }
        state = .none
    }

    /// Clears the last check's error or result as the user goes to choose another backup, so the screen asks for one
    /// again, and the same error again is a change the UI sees.
    public func clearResult() {
        switch state {
        case .error, .opened: state = .none
        case .none, .needsPasswordEntry: break
        }
    }
}
