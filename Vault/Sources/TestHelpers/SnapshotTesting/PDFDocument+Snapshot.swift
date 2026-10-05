import Foundation
import PDFKit
import SnapshotTesting
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
extension Snapshotting where Value == PDFDocument, Format == UIImage {
    /// Snapshots a PDF as an image, so we don't worry about metadata/non-visible aspects of the PDF.
    public static func pdf(page: Int = 1) -> Snapshotting {
        .init(
            pathExtension: "png",
            diffing: .image,
            snapshot: { pdfDocument in
                pdfDocument.asImage(page: page) ?? UIImage()
            },
        )
    }
}

extension PDFDocument {
    fileprivate func asImage(page: Int = 1) -> UIImage? {
        guard let data = dataRepresentation() else { return nil }
        let cfData = data as CFData
        guard let provider = CGDataProvider(data: cfData) else { return nil }
        guard let pdfDoc = CGPDFDocument(provider) else { return nil }
        guard let page = pdfDoc.page(at: page) else { return nil }

        let pageRect = page.getBoxRect(.mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(pageRect)

            ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)

            ctx.cgContext.drawPDFPage(page)
        }
    }
}
#elseif canImport(AppKit)
extension Snapshotting where Value == PDFDocument, Format == NSImage {
    /// Snapshots a PDF as an image, so we don't worry about metadata/non-visible aspects of the PDF.
    ///
    /// Drawn at a scale of 3, whatever the Mac's displays, so the snapshot is the same on every Mac. That's the scale
    /// the iPhone's snapshots have, and the backup's QR codes are drawn at, so their modules land on whole pixels.
    ///
    /// Every pixel has to match, but each colour only nearly: macOS turns some of a PDF's colours into the display's
    /// own on the way, and the display's colours change while the screen is locked. A QR code's module that changed
    /// would still fail.
    public static func pdf(page: Int = 1) -> Snapshotting {
        .init(
            pathExtension: "png",
            diffing: .image(channelTolerance: 12),
            snapshot: { pdfDocument in
                pdfDocument.asImage(page: page) ?? NSImage()
            },
        )
    }
}

extension PDFDocument {
    fileprivate func asImage(page: Int = 1) -> NSImage? {
        let scale: CGFloat = 3
        guard let data = dataRepresentation() else { return nil }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        guard let pdfDoc = CGPDFDocument(provider) else { return nil }
        guard let page = pdfDoc.page(at: page) else { return nil }

        let pageRect = page.getBoxRect(.mediaBox)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(pageRect.width * scale),
                  height: Int(pageRect.height * scale),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(pageRect)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return nil }
        // Exactly a third of its pixels in points, so it's written out as these pixels. Otherwise AppKit draws it again
        // at the scale of the Mac's screen, which a locked screen leaves at 1.
        return NSImage(
            cgImage: image,
            size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale),
        )
    }
}
#endif
