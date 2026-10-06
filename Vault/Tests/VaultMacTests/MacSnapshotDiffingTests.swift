import AppKit
import SnapshotTesting
import TestHelpers
import Testing

/// The Mac snapshots' comparison: colours only have to be close, but every pixel has to be there.
struct MacSnapshotDiffingTests {
    @Test
    func sameImage_matches() {
        let sut = Diffing<NSImage>.image(channelTolerance: 12)

        #expect(sut.diffV2(image(gray: 100), image(gray: 100)) == nil)
    }

    @Test
    func coloursWithinTheTolerance_match() {
        let sut = Diffing<NSImage>.image(channelTolerance: 12)

        #expect(sut.diffV2(image(gray: 100), image(gray: 110)) == nil)
    }

    @Test
    func coloursBeyondTheTolerance_dontMatch() {
        let sut = Diffing<NSImage>.image(channelTolerance: 12)

        #expect(sut.diffV2(image(gray: 0), image(gray: 255)) != nil)
    }

    @Test
    func oneChangedPixel_doesntMatch() {
        let sut = Diffing<NSImage>.image(channelTolerance: 12)

        #expect(sut.diffV2(image(gray: 0), image(gray: 0, whitePixels: 1)) != nil)
    }

    @Test
    func changedPixelsWithinTheAllowedFraction_match() {
        let sut = Diffing<NSImage>.image(channelTolerance: 12, allowedFractionDiffering: 0.01)

        // 1 of 100 pixels.
        #expect(sut.diffV2(image(gray: 0), image(gray: 0, whitePixels: 1)) == nil)
        #expect(sut.diffV2(image(gray: 0), image(gray: 0, whitePixels: 2)) != nil)
    }

    @Test
    func differentSizes_dontMatch() {
        let sut = Diffing<NSImage>.image(channelTolerance: 255)

        #expect(sut.diffV2(image(gray: 0), image(gray: 0, side: 11)) != nil)
    }

    /// A square of `gray`, its first `whitePixels` white.
    private func image(gray: UInt8, whitePixels: Int = 0, side: Int = 10) -> NSImage {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in 0 ..< side * side {
            let value = pixel < whitePixels ? 255 : gray
            bytes[pixel * 4] = value
            bytes[pixel * 4 + 1] = value
            bytes[pixel * 4 + 2] = value
            bytes[pixel * 4 + 3] = 255
        }
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4,
            bitsPerPixel: 32,
        )!
        bytes.withUnsafeBytes { buffer in
            representation.bitmapData?.update(
                from: buffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                count: buffer.count,
            )
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(representation)
        return image
    }
}
