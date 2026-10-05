import Foundation
import PDFKit
import TestHelpers
import Testing
import VaultCore
@testable import VaultBackup

struct VaultBackupPDFDetatcherImplTests {
    @Test
    func detachEncryptedVault_decodesIfPresent() throws {
        let sut = makeSUT()
        let pdf = PDFDocument.onePage
        let annotation = try makeVaultAnnotation(vault: anyEncryptedVault())
        pdf.page(at: 0)?.addAnnotation(annotation)

        let result = try sut.detachEncryptedVault(fromPDF: pdf)

        #expect(result == anyEncryptedVault())
    }

    @Test
    func detachEncryptedVault_noPagesThrowsError() throws {
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.detachEncryptedVault(fromPDF: .noPages)
        }
    }

    @Test
    func detachEncryptedVault_noAnnotationsThrowsError() throws {
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.detachEncryptedVault(fromPDF: .onePage)
        }
    }

    @Test
    func detachEncryptedVault_missingPayloadThrowsError() throws {
        let sut = makeSUT()
        let pdf = PDFDocument.onePage
        let annotation = makeEmptyAnnotation()
        pdf.page(at: 0)?.addAnnotation(annotation)

        #expect(throws: (any Error).self) {
            try sut.detachEncryptedVault(fromPDF: pdf)
        }
    }

    @Test
    func detachEncryptedVault_invalidDataThrowsError() throws {
        let sut = makeSUT()
        let pdf = PDFDocument.onePage
        let annotation = makeInvalidDataAnnotation()
        pdf.page(at: 0)?.addAnnotation(annotation)

        #expect(throws: (any Error).self) {
            try sut.detachEncryptedVault(fromPDF: pdf)
        }
    }
}

// MARK: - Helpers

extension VaultBackupPDFDetatcherImplTests {
    private func makeSUT() -> VaultBackupPDFDetatcherImpl {
        .init()
    }

    private func anyEncryptedVault() -> EncryptedVault {
        EncryptedVault(
            version: "1.0.0",
            data: Data(),
            authentication: Data(),
            encryptionIV: Data(),
            keygenSalt: Data(),
            keygenSignature: "my-signature",
        )
    }

    private func makeVaultAnnotation(vault: EncryptedVault) throws -> PDFAnnotation {
        let annotation = PDFAnnotation(
            bounds: CGRect(x: -100, y: -100, width: 100, height: 100),
            forType: .circle,
            withProperties: nil,
        )
        let encoded = try makeEncodedVault(vault: vault)
        annotation.contents = "\(VaultIdentifiers.Backup.encryptedVaultData):" + encoded
        return annotation
    }

    private func makeEmptyAnnotation() -> PDFAnnotation {
        let annotation = PDFAnnotation(
            bounds: CGRect(x: -100, y: -100, width: 100, height: 100),
            forType: .circle,
            withProperties: nil,
        )
        annotation.contents = "\(VaultIdentifiers.Backup.encryptedVaultData):"
        return annotation
    }

    private func makeInvalidDataAnnotation() -> PDFAnnotation {
        let annotation = PDFAnnotation(
            bounds: CGRect(x: -100, y: -100, width: 100, height: 100),
            forType: .circle,
            withProperties: nil,
        )
        annotation.contents = "\(VaultIdentifiers.Backup.encryptedVaultData):AAAAA"
        return annotation
    }

    private func makeEncodedVault(vault: EncryptedVault) throws -> String {
        let coder = EncryptedVaultCoder()
        let encodedVault = try coder.encode(vault: vault)
        return encodedVault.base64EncodedString()
    }
}

extension PDFDocument {
    fileprivate static var noPages: PDFDocument {
        PDFDocument()
    }

    fileprivate static var onePage: PDFDocument {
        #if canImport(UIKit)
        let renderer = UIGraphicsPDFRenderer()
        let data = renderer.pdfData { context in
            context.beginPage()
        }
        return PDFDocument(data: data)!
        #else
        // The same blank US Letter page, drawn with Core Graphics, as the Mac has no UIGraphicsPDFRenderer.
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &mediaBox, nil)!
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return PDFDocument(data: data as Data)!
        #endif
    }
}
