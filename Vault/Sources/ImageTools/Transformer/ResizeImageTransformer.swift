#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct ResizeImageTransformer: ImageTransformer {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    #if canImport(UIKit)
    public func tranform(image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    #else
    /// The scale the Mac draws at: the iPhone's, whose screen iOS draws for, so a backup has the same detail whichever
    /// device makes it.
    static let scale: CGFloat = 3

    public func tranform(image: NSImage) -> NSImage {
        let width = Int((size.width * Self.scale).rounded(.up))
        let height = Int((size.height * Self.scale).rounded(.up))
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else {
            return image
        }
        // Nearest neighbour, so a QR code's modules stay sharp.
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else {
            return image
        }
        return NSImage(cgImage: resized, size: size)
    }
    #endif
}
