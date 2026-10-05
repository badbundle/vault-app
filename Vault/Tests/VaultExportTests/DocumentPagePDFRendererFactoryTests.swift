// The Mac renders PDFs from VAULT-104.
#if canImport(UIKit)
import Foundation
import Testing
import UIKit
import VaultExport

struct DocumentPagePDFRendererFactoryTests {
    @Test(arguments: [USLetterDocumentSize(), A4DocumentSize()] as [any PDFDocumentSize])
    func makeRenderer_rendererHasSpecifiedSizeSet(documentSize: any PDFDocumentSize) {
        let sut = makeSUT(size: documentSize)

        let renderer = sut.makeRenderer()

        let expectedSize = documentSize.pointSize()
        let actualSize = renderer.format.bounds.size
        #expect(actualSize.width.isAlmostEqual(to: expectedSize.width))
        #expect(actualSize.height.isAlmostEqual(to: expectedSize.height))
    }

    @Test(arguments: [USLetterDocumentSize(), A4DocumentSize()] as [any PDFDocumentSize])
    func makeRenderer_rendererStartsAtOrigin(documentSize: any PDFDocumentSize) {
        let sut = makeSUT(size: documentSize)

        let renderer = sut.makeRenderer()

        let actualOrigin = renderer.format.bounds.origin
        #expect(actualOrigin == .zero)
    }

    @Test(arguments: ["", "one", "two"])
    func makeRenderer_formatCreatorIsApplicationName(applicationName: String) throws {
        let sut = makeSUT(applicationName: applicationName)

        let renderer = sut.makeRenderer()

        let format = try #require(renderer.format as? UIGraphicsPDFRendererFormat)
        #expect(format.documentInfo(forKey: kCGPDFContextCreator) as? String? == applicationName)
    }

    @Test(arguments: ["", "one", "two"])
    func makeRenderer_formatAuthorIsAuthorName(authorName: String) throws {
        let sut = makeSUT(authorName: authorName)

        let renderer = sut.makeRenderer()

        let format = try #require(renderer.format as? UIGraphicsPDFRendererFormat)
        #expect(format.documentInfo(forKey: kCGPDFContextAuthor) as? String? == authorName)
    }

    @Test(arguments: ["", "one", "two"])
    func makeRenderer_formatDocumentTitleIsDocumentTitle(documentTitle: String) throws {
        let sut = makeSUT(documentTitle: documentTitle)

        let renderer = sut.makeRenderer()

        let format = try #require(renderer.format as? UIGraphicsPDFRendererFormat)
        #expect(format.documentInfo(forKey: kCGPDFContextTitle) as? String? == documentTitle)
    }

    // MARK: - Helpers

    private func makeSUT(
        size: any PDFDocumentSize = USLetterDocumentSize(),
        applicationName: String? = "Any",
        authorName: String? = "Any",
        documentTitle: String? = "Any",
    ) -> PDFDocumentPageRendererFactory {
        PDFDocumentPageRendererFactory(
            size: size,
            applicationName: applicationName,
            authorName: authorName,
            documentTitle: documentTitle,
        )
    }
}

extension UIGraphicsPDFRendererFormat {
    fileprivate func documentInfo(forKey key: String) -> Any? {
        documentInfo[key]
    }

    fileprivate func documentInfo(forKey key: CFString) -> Any? {
        documentInfo[key as String]
    }
}
#endif
