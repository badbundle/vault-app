#if os(macOS)
import AppKit
import SnapshotTesting

extension Diffing where Value == NSImage {
    /// Images that match pixel for pixel, at the same size, with each colour channel of every pixel within
    /// `channelTolerance` of the reference's (out of 255), except for at most `allowedFractionDiffering` of them.
    ///
    /// SnapshotTesting's perceptual precision would allow the same, but it throws inside Core Image on macOS 27 as
    /// soon as two images differ, so the Mac's snapshots compare this way instead.
    public static func image(channelTolerance: Int, allowedFractionDiffering: Double = 0) -> Diffing {
        .diff(
            toData: { $0.pngData() ?? Data() },
            fromData: { NSImage(data: $0) ?? NSImage() },
            diffV2: { reference, snapshot in
                guard let expected = RGBAPixels(reference), let actual = RGBAPixels(snapshot) else {
                    return ("Couldn't read the snapshot or its reference.", [])
                }
                guard expected.width == actual.width, expected.height == actual.height else {
                    return (
                        "Newly-taken snapshot is \(actual.width)×\(actual.height), but its reference is " +
                            "\(expected.width)×\(expected.height).",
                        attachments(reference, snapshot),
                    )
                }
                let different = expected.countOfPixelsDiffering(from: actual, byMoreThan: channelTolerance)
                let allowed = Int(Double(expected.width * expected.height) * allowedFractionDiffering)
                guard different > allowed else { return nil }
                return (
                    "Newly-taken snapshot does not match reference: \(different) pixels differ by more than " +
                        "\(channelTolerance) in a channel, and at most \(allowed) may.",
                    attachments(reference, snapshot),
                )
            },
        )
    }

    private static func attachments(_ reference: NSImage, _ snapshot: NSImage) -> [DiffAttachment] {
        [
            .data(reference.pngData() ?? Data(), name: "reference.png"),
            .data(snapshot.pngData() ?? Data(), name: "failure.png"),
        ]
    }
}

/// An image's pixels, as 8-bit sRGB with alpha.
private struct RGBAPixels {
    var width: Int
    var height: Int
    var bytes: [UInt8]

    init?(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        width = cgImage.width
        height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    func countOfPixelsDiffering(from other: RGBAPixels, byMoreThan tolerance: Int) -> Int {
        var count = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0 ..< 4
                where abs(Int(bytes[pixel + channel]) - Int(other.bytes[pixel + channel])) > tolerance
            {
                count += 1
                break
            }
        }
        return count
    }
}

extension NSImage {
    fileprivate func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = size
        return representation.representation(using: .png, properties: [:])
    }
}
#endif
