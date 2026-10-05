import Foundation
import PDFKit
import VaultCore

/// @mockable
protocol VaultBackupPDFAttacher {
    /// Attaches the encrypted vault to the PDF in a way that we can detatch and read it easily.
    func attach(vault: EncryptedVault, to pdf: inout PDFDocument) throws
}

final class VaultBackupPDFAttacherImpl: VaultBackupPDFAttacher {
    init() {}

    enum AttacherError: Error {
        case noPagesGenerated
    }

    func attach(vault: EncryptedVault, to pdf: inout PDFDocument) throws {
        guard let firstPage = pdf.page(at: 0) else {
            throw AttacherError.noPagesGenerated
        }
        let vaultAnnotation = try makeVaultAnnotation(vault: vault)
        firstPage.addAnnotation(vaultAnnotation)
    }

    private func makeVaultAnnotation(vault: EncryptedVault) throws -> PDFAnnotation {
        let annotation = PDFAnnotation(
            bounds: CGRect(x: -100, y: -100, width: 100, height: 100),
            forType: .circle,
            withProperties: nil,
        )
        let encoded = try makeEncodedVault(vault: vault)
        annotation.contents = "\(VaultIdentifiers.Backup.encryptedVaultData):" + encoded
        annotation.color = .clear
        annotation.fontColor = .clear
        annotation.backgroundColor = .clear
        return annotation
    }

    private func makeEncodedVault(vault: EncryptedVault) throws -> String {
        let coder = EncryptedVaultCoder()
        let encodedVault = try coder.encode(vault: vault)
        return encodedVault.base64EncodedString()
    }
}
