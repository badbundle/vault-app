import ImageTools
#if canImport(UIKit)
import UIKit

extension UIImage {
    static func from(color: UIColor, size: CGSize = .init(width: 1, height: 1)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#elseif canImport(AppKit)
import AppKit

extension NSImage {
    /// A bitmap of `color` in sRGB, so it's the same colour in a PDF whatever the Mac's display. An image drawn by a
    /// handler takes on the display's colours, which change while the screen is locked.
    static func from(color: NSColor, size: CGSize = .init(width: 1, height: 1)) -> NSImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let srgb = color.usingColorSpace(.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(size.width),
                  height: Int(size.height),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return NSImage() }
        context.setFillColor(srgb.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        guard let image = context.makeImage() else { return NSImage() }
        return NSImage(cgImage: image, size: size)
    }
}
#endif
