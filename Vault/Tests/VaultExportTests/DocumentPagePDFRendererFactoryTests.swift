import CoreGraphics
import Foundation
import Testing
import VaultExport
#if canImport(UIKit)
import UIKit
#endif

struct DocumentPagePDFRendererFactoryTests {
    @Test(arguments: [USLetterDocumentSize(), A4DocumentSize()] as [any PDFDocumentSize])
    func makeRenderer_rendererHasSpecifiedSizeSet(documentSize: any PDFDocumentSize) {
        let sut = makeSUT(size: documentSize)

        let renderer = sut.makeRenderer()

        let expectedSize = documentSize.pointSize()
        let actualSize = renderer.pageBounds.size
        #expect(actualSize.width.isAlmostEqual(to: expectedSize.width))
        #expect(actualSize.height.isAlmostEqual(to: expectedSize.height))
    }

    @Test(arguments: [USLetterDocumentSize(), A4DocumentSize()] as [any PDFDocumentSize])
    func makeRenderer_rendererStartsAtOrigin(documentSize: any PDFDocumentSize) {
        let sut = makeSUT(size: documentSize)

        let renderer = sut.makeRenderer()

        let actualOrigin = renderer.pageBounds.origin
        #expect(actualOrigin == .zero)
    }

    @Test(arguments: ["", "one", "two"])
    func makeRenderer_formatCreatorIsApplicationName(applicationName: String) throws {
        let sut = makeSUT(applicationName: applicationName)

        let renderer = sut.makeRenderer()

        #expect(try renderer.documentInfo(forKey: kCGPDFContextCreator) as? String? == applicationName)
    }

    @Test(arguments: ["", "one", "two"])
    func makeRenderer_formatAuthorIsAuthorName(authorName: String) throws {
        let sut = makeSUT(authorName: authorName)

        let renderer = sut.makeRenderer()

        #expect(try renderer.documentInfo(forKey: kCGPDFContextAuthor) as? String? == authorName)
    }

    @Test(arguments: ["", "one", "two"])
    func makeRenderer_formatDocumentTitleIsDocumentTitle(documentTitle: String) throws {
        let sut = makeSUT(documentTitle: documentTitle)

        let renderer = sut.makeRenderer()

        #expect(try renderer.documentInfo(forKey: kCGPDFContextTitle) as? String? == documentTitle)
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

extension PlatformPDFRenderer {
    /// The bounds of each page.
    fileprivate var pageBounds: CGRect {
        #if canImport(UIKit)
        format.bounds
        #else
        bounds
        #endif
    }

    /// The value the document's info dictionary has for the key.
    fileprivate func documentInfo(forKey key: CFString) throws -> Any? {
        #if canImport(UIKit)
        let format = try #require(format as? UIGraphicsPDFRendererFormat)
        return format.documentInfo[key as String]
        #else
        return documentInfo[key as String]
        #endif
    }
}
