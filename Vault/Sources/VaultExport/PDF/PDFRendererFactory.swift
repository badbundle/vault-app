import CoreGraphics
import Foundation

/// Creates a rendering context where PDFs will be drawn onto.
/// @mockable
public protocol PDFRendererFactory {
    var size: any PDFDocumentSize { get }
    func makeRenderer() -> PlatformPDFRenderer
}

extension PDFRendererFactory {
    public func makeRenderer() -> PlatformPDFRenderer {
        let size = size.pointSize()
        return PlatformPDFRenderer(bounds: .init(origin: .zero, size: .init(width: size.width, height: size.height)))
    }
}
