import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import VaultAppIcon

/// Turns `VaultAppIconView` into PNG bytes.
///
/// Uses ImageIO rather than AppKit or UIKit so it compiles for every platform the
/// package supports: CI builds the executable for the iOS Simulator through its
/// test target, and `swift run` builds it for the Mac.
enum AppIconPNGRenderer {
    enum Failure: Error {
        case renderFailed(VaultAppIconAppearance)
        case encodeFailed
    }

    /// Renders one appearance, `pixelSize` square.
    ///
    /// `ImageRenderer` is main-actor bound; handing back `Data` means a `CGImage`
    /// never has to cross an isolation boundary.
    @MainActor
    static func pngData(appearance: VaultAppIconAppearance, pixelSize: Int) throws -> Data {
        let side = CGFloat(pixelSize)
        let renderer = ImageRenderer(
            content: VaultAppIconView(appearance: appearance)
                .frame(width: side, height: side),
        )
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: side, height: side)
        renderer.isOpaque = appearance.hasOpaqueBackground
        guard let rendered = renderer.cgImage else {
            throw Failure.renderFailed(appearance)
        }
        // App Store icons may not carry an alpha channel, so the default icon is
        // redrawn without one whatever the renderer produced. The dark and tinted
        // variants keep theirs: Apple supplies the backgrounds behind them.
        let image = try appearance.hasOpaqueBackground ? withoutAlpha(rendered) : rendered
        return try encodePNG(image)
    }

    static func withoutAlpha(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ) else {
            throw Failure.encodeFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let opaque = context.makeImage() else {
            throw Failure.encodeFailed
        }
        return opaque
    }

    static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil,
        ) else {
            throw Failure.encodeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.encodeFailed
        }
        return data as Data
    }
}
