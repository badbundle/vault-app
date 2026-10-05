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
    static func from(color: NSColor, size: CGSize = .init(width: 1, height: 1)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }
}
#endif
