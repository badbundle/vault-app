import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Creates a rendering context where PDFs will be drawn onto.
/// @mockable
public protocol PDFRendererFactory {
    var size: any PDFDocumentSize { get }
    // The Mac renders PDFs from VAULT-104. Inside the protocol, so mockolo still makes its mock.
    #if canImport(UIKit)
    func makeRenderer() -> UIGraphicsPDFRenderer
    #endif
}

#if canImport(UIKit)
extension PDFRendererFactory {
    public func makeRenderer() -> UIGraphicsPDFRenderer {
        let size = size.pointSize()
        return UIGraphicsPDFRenderer(bounds: .init(origin: .zero, size: .init(width: size.width, height: size.height)))
    }
}
#endif
