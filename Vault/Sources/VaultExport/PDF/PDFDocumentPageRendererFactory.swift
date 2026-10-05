import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Produces renderers optimized for rendering a standard size document.
///
/// Contains information about the size of PDF to render and metadata that will be associated with the PDF.
public struct PDFDocumentPageRendererFactory: PDFRendererFactory {
    public var size: any PDFDocumentSize
    public var documentTitle: String?
    public var applicationName: String?
    public var authorName: String?

    public init(
        size: any PDFDocumentSize,
        applicationName: String? = nil,
        authorName: String? = nil,
        documentTitle: String? = nil,
    ) {
        self.size = size
        self.applicationName = applicationName
        self.authorName = authorName
        self.documentTitle = documentTitle
    }

    public func makeRenderer() -> PlatformPDFRenderer {
        #if canImport(UIKit)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetadata as [String: Any]

        return UIGraphicsPDFRenderer(bounds: pageRect(), format: format)
        #else
        return CoreGraphicsPDFRenderer(bounds: pageRect(), documentInfo: pdfMetadata as [String: Any])
        #endif
    }
}

// MARK: - Helpers

extension PDFDocumentPageRendererFactory {
    private func pageRect() -> CGRect {
        let (pageWidth, pageHeight) = size.pointSize()
        let size = CGSize(width: pageWidth, height: pageHeight)
        return CGRect(origin: .zero, size: size)
    }

    private var pdfMetadata: [CFString: String] {
        var metadata = [CFString: String]()
        metadata[kCGPDFContextCreator] = applicationName
        metadata[kCGPDFContextAuthor] = authorName
        metadata[kCGPDFContextTitle] = documentTitle
        return metadata
    }
}
