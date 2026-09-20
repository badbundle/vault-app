import Foundation
import PDFKit
import TestHelpers
import Testing
import VaultExport
@testable import VaultBackup

struct VaultExportPDFDocumentRendererTests {
    @Test
    func init_doesNotHaveAnySideEffects() {
        let renderer = PDFDocumentRendererMock()

        _ = makeSUT(documentRenderer: renderer)

        #expect(renderer.renderCallCount == 0)
    }

    @Test
    func render_rendersVaultParsedToDocument() throws {
        let exportPayload = VaultExportPayload(
            encryptedVault: EncryptedVault(
                version: "1.0.0",
                data: Data(),
                authentication: Data(),
                encryptionIV: Data(),
                keygenSalt: Data(),
                keygenSignature: "my-signature",
            ),
            userDescription: "my vault",
            created: Date(timeIntervalSince1970: 2000),
        )
        let pdfDocument = PDFDocument()
        let renderer = makeRendererMock(pdfDocument: pdfDocument)
        let sut = makeSUT(documentRenderer: renderer)

        let document = try sut.render(document: exportPayload)

        #expect(
            document === pdfDocument,
            "Document should be returned from the block renderer",
        )
        #expect(renderer.renderCallCount == 2, "Renders twice, first pass and final render")
        #expect(renderer.renderArgValues.last?.content.count == 4)
    }

    @Test
    func render_attachesBackupPayload() throws {
        let exportPayload = VaultExportPayload(
            encryptedVault: EncryptedVault(
                version: "1.0.0",
                data: Data(),
                authentication: Data(),
                encryptionIV: Data(),
                keygenSalt: Data(),
                keygenSignature: "my-signature",
            ),
            userDescription: "my vault",
            created: Date(timeIntervalSince1970: 2000),
        )
        let attacher = VaultBackupPDFAttacherMock()
        let sut = makeSUT(attacher: attacher)

        _ = try sut.render(document: exportPayload)

        #expect(attacher.attachCallCount == 1)
    }

    @Test
    func render_mapsFirstPassToFirstHalfAndSecondPassToSecondHalf() throws {
        let renderer = PDFDocumentRendererMock()
        renderer.renderHandler = { _, progress in
            progress(0.5)
            progress(1)
            return PDFDocument()
        }
        let sut = makeSUT(documentRenderer: renderer)
        var reported = [Double]()

        _ = try sut.render(document: anyExportPayload()) { reported.append($0) }

        #expect(reported == [0.25, 0.5, 0.75, 1])
    }
}

// MARK: - Helpers

extension VaultExportPDFDocumentRendererTests {
    private func makeSUT(
        documentRenderer: PDFDocumentRendererMock = makeRendererMock(),
        attacher: VaultBackupPDFAttacherMock = VaultBackupPDFAttacherMock(),
        file _: StaticString = #filePath,
        line _: UInt = #line,
    ) -> VaultExportPDFDocumentRenderer<PDFDocumentRendererMock> {
        VaultExportPDFDocumentRenderer(
            renderer: documentRenderer,
            dataShardBuilder: DataShardBuilder(),
            attacher: attacher,
        )
    }

    private func anyExportPayload() -> VaultExportPayload {
        VaultExportPayload(
            encryptedVault: EncryptedVault(
                version: "1.0.0",
                data: Data(),
                authentication: Data(),
                encryptionIV: Data(),
                keygenSalt: Data(),
                keygenSignature: "my-signature",
            ),
            userDescription: "my vault",
            created: Date(timeIntervalSince1970: 2000),
        )
    }
}

private func makeRendererMock(pdfDocument: PDFDocument = PDFDocument()) -> PDFDocumentRendererMock {
    let renderer = PDFDocumentRendererMock()
    renderer.renderHandler = { _, _ in pdfDocument }
    return renderer
}
