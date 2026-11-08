import Foundation
import PDFKit
import VaultBackup

/// Reads the backup out of a backup PDF, for restoring it (`BackupImportFlowViewModel`) or checking it
/// (`BackupCheckViewModel`), so both read a file the same way and say the same about one they can't read.
enum BackupPDFReader {
    struct InvalidPDFError: Error {}

    /// The encrypted backup the PDF carries, read off the main actor: a large vault's PDF takes a while to read.
    static func encryptedVault(
        fromPDF pdfDataResult: Result<Data, any Error>,
        using backupPDFDetatcher: any VaultBackupPDFDetatcher,
    ) async throws -> EncryptedVault {
        let data = pdfDataResult.mapError { error in
            PresentationError(
                userTitle: "File Error",
                userDescription: "There was an error with the file you selected. Please try again.",
                debugDescription: error.localizedDescription,
            )
        }
        guard let pdf = try PDFDocument(data: data.get()) else { throw InvalidPDFError() }
        return try backupPDFDetatcher.detachEncryptedVault(fromPDF: pdf)
    }

    /// What to show for an error reading a backup.
    static func presentationError(for error: any Error) -> PresentationError {
        if let error = error as? any LocalizedError {
            return PresentationError(localizedError: error)
        }
        return PresentationError(
            userTitle: "Document Error",
            userDescription: "There was an error with the this Vault export document. Please check the document, your internet, and try again.",
            debugDescription: error.localizedDescription,
        )
    }
}
