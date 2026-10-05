#if os(macOS)
import AppKit
import SnapshotTesting
import SwiftUI

extension Snapshotting where Value: SwiftUI.View, Format == NSImage {
    /// The view as a Mac window shows it, on the window's background: at a fixed size in points, drawn at a scale of 2
    /// whatever this Mac's displays, in light or dark (docs/mac-app.md, "Validation").
    ///
    /// The Mac's text antialiasing, and some colours, differ a little from one run to the next, so each pixel's colours
    /// only have to be close, and 1% of pixels may differ more, at the edges of text.
    @MainActor
    public static func macWindow(
        width: CGFloat,
        height: CGFloat,
        appearance: NSAppearance.Name = .aqua,
    ) -> Snapshotting {
        Snapshotting<NSImage, NSImage>(
            pathExtension: "png",
            diffing: .image(channelTolerance: 12, allowedFractionDiffering: 0.01),
        ).pullback { view in
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            let host = NSHostingView(
                rootView: view
                    .frame(width: width, height: height)
                    .background(Color(nsColor: .windowBackgroundColor)),
            )
            host.frame = frame
            // In a window, so controls draw as they do on screen, but never shown. Its scale is 2 whatever the Mac's
            // displays, which a locked screen leaves at 1, so text is drawn at the same resolution every run.
            let window = FixedScaleWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            return host.image(scale: 2)
        }
    }
}

/// A window that draws at a scale of 2, whatever screen it would be on.
private final class FixedScaleWindow: NSWindow {
    override var backingScaleFactor: CGFloat {
        2
    }
}

extension NSView {
    /// What the view draws, at `scale` pixels to the point.
    @MainActor
    fileprivate func image(scale: CGFloat) -> NSImage {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0,
        ) else {
            return NSImage()
        }
        representation.size = bounds.size
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }
}
#endif
