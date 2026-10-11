import Foundation
import PDFKit
import VaultCore

/// @mockable
public protocol VaultBackupPDFDetatcher: Sendable {
    /// Detatches the `EncryptedVault` from the PDF if it is able.
    func detachEncryptedVault(fromPDF pdf: PDFDocument) throws -> EncryptedVault
}

public final class VaultBackupPDFDetatcherImpl: VaultBackupPDFDetatcher {
    public init() {}

    public enum ExtractionError: Error, LocalizedError {
        case missingData
        case noPages
        case noAnnotations
        case malformedBase64Data

        public var errorDescription: String? {
            "Not a Vault Export"
        }

        public var failureReason: String? {
            "This is not a vault export or the data has been modified. Please scan the QR codes manually."
        }
    }

    public func detachEncryptedVault(fromPDF pdf: PDFDocument) throws -> EncryptedVault {
        guard let firstPage = pdf.page(at: 0) else {
            throw ExtractionError.noPages
        }
        guard let annotation = firstPage.annotations
            .first(where: { $0.contents?.starts(with: VaultIdentifiers.Backup.encryptedVaultData) == true })
        else {
            throw ExtractionError.noAnnotations
        }
        guard let contents = annotation.contents else {
            throw ExtractionError.noAnnotations
        }
        guard let encodedString = contents.split(separator: ":")[safeIndex: 1] else {
            throw ExtractionError.missingData
        }
        guard let data = Data(base64Encoded: String(encodedString)) else {
            throw ExtractionError.malformedBase64Data
        }
        return try EncryptedVaultCoder().decode(vaultData: data)
    }
}
