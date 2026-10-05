#if canImport(UIKit)
import UIKit

/// The platform's image type: `UIImage` on iOS, `NSImage` on the Mac.
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit

/// The platform's image type: `UIImage` on iOS, `NSImage` on the Mac.
public typealias PlatformImage = NSImage

extension NSImage {
    /// The image as PNG data, as `UIImage.pngData()` gives it on iOS, or `nil` if it can't be drawn.
    public func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
#endif
