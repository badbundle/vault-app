#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import CoreGraphics
import Foundation

/// Draws a PDF with Core Graphics on the Mac, as `UIGraphicsPDFRenderer` does on iOS.
///
/// Each page is drawn in UIKit's coordinates, with the origin at its top left, and AppKit's text and image drawing goes
/// into the current page. So the same drawing code makes the same pages on both platforms.
open class CoreGraphicsPDFRenderer {
    /// The size of every page. Empty bounds give US Letter pages, as they do for `UIGraphicsPDFRenderer`.
    public let bounds: CGRect
    /// The document's info dictionary, such as its title and creator (`kCGPDFContextTitle` and so on).
    public let documentInfo: [String: Any]

    public init(bounds: CGRect, documentInfo: [String: Any] = [:]) {
        self.bounds = bounds
        self.documentInfo = documentInfo
    }

    /// Draws US Letter pages, as `UIGraphicsPDFRenderer()` does.
    public convenience init() {
        self.init(bounds: .zero)
    }

    /// US Letter, in points: what PDF contexts draw on when they're given no page size.
    private static let usLetter = CGRect(x: 0, y: 0, width: 612, height: 792)

    /// Draws the document, and returns it as PDF data.
    ///
    /// `actions` begins each page with `beginPage()`, then draws into it, with AppKit or the context's `cgContext`.
    open func pdfData(actions: (CoreGraphicsPDFRendererContext) -> Void) -> Data {
        let data = NSMutableData()
        var mediaBox = bounds.isEmpty ? Self.usLetter : bounds
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let cgContext = CGContext(consumer: consumer, mediaBox: &mediaBox, documentInfo as CFDictionary)
        else {
            return Data()
        }
        let context = CoreGraphicsPDFRendererContext(cgContext: cgContext, bounds: mediaBox)
        NSGraphicsContext.saveGraphicsState()
        // Flipped, as each page's coordinates are: AppKit draws text and images the right way up.
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: true)
        actions(context)
        context.endPageIfNeeded()
        NSGraphicsContext.restoreGraphicsState()
        cgContext.closePDF()
        return data as Data
    }
}

/// The context `CoreGraphicsPDFRenderer` draws a PDF in, as `UIGraphicsPDFRendererContext` is for
/// `UIGraphicsPDFRenderer`.
public final class CoreGraphicsPDFRendererContext {
    /// The Core Graphics context of the page being drawn.
    public let cgContext: CGContext
    /// The bounds of each page.
    public let pdfContextBounds: CGRect
    private var isInPage = false

    init(cgContext: CGContext, bounds: CGRect) {
        self.cgContext = cgContext
        pdfContextBounds = bounds
    }

    /// Ends the page being drawn, if there is one, and begins the next. Its origin is at its top left.
    public func beginPage() {
        endPageIfNeeded()
        cgContext.beginPDFPage(nil)
        isInPage = true
        cgContext.translateBy(x: 0, y: pdfContextBounds.height)
        cgContext.scaleBy(x: 1, y: -1)
    }

    func endPageIfNeeded() {
        guard isInPage else { return }
        cgContext.endPDFPage()
        isInPage = false
    }
}
#endif
