import CoreGraphics
import Foundation

/// The picture of a `BackupSeal`, drawn in the style of an SF Symbol: an eight-pointed badge in one of Apple's system
/// colors, with a white dial on it, like the dial on Vault's door.
///
/// The dial is two rings, each with a gap, and a dot in the middle. The badge's color, and where each ring's gap is
/// and how wide, come from the seal's digest, so two seals look different at a glance, and the same seal looks the
/// same everywhere it's drawn: on a PDF backup, and on screen on iOS and the Mac. Which byte drives what never changes,
/// as printed seals have to keep matching.
public struct BackupSealArtwork: Sendable {
    public let seal: BackupSeal

    public init(seal: BackupSeal) {
        self.seal = seal
    }

    /// The badge's color, in sRGB.
    public var color: CGColor {
        let (red, green, blue) = Self.palette[Int(seal.digest[0]) % Self.palette.count]
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// Draws the seal in the largest square that fits in `rect`, centred.
    ///
    /// `context`'s y axis has to point down, as it does in UIKit, in SwiftUI's `Canvas` and in Vault's PDFs on both
    /// platforms: drawn the other way up, the seal would come out mirrored.
    public func draw(in context: CGContext, rect: CGRect) {
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0 else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)

        context.saveGState()
        defer { context.restoreGState() }

        context.addPath(badge(center: center, radius: radius))
        context.setFillColor(color)
        context.fillPath()

        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        context.setStrokeColor(white)
        context.setLineWidth(radius * 0.09)
        context.setLineCap(.round)
        for ring in rings {
            // The gap is centred on `ring.gapAngle`: the ring runs from one side of it the long way round to the other.
            context.addArc(
                center: center,
                radius: radius * ring.radius,
                startAngle: ring.gapAngle + ring.gapWidth / 2,
                endAngle: ring.gapAngle + 2 * .pi - ring.gapWidth / 2,
                clockwise: false,
            )
            context.strokePath()
        }

        let dot = radius * 0.14
        context.setFillColor(white)
        context.fillEllipse(in: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot))
    }

    /// An eight-pointed star with every corner rounded, outer and inner, as SF Symbols' seal is.
    private func badge(center: CGPoint, radius: CGFloat) -> CGPath {
        // Where two squares, one turned 45°, would cross.
        let inner = radius * cos(.pi / 4) / cos(.pi / 8)
        let points = (0 ..< 16).map { index -> CGPoint in
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / 8
            let distance = index.isMultiple(of: 2) ? radius : inner
            return CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: (points[15].x + points[0].x) / 2, y: (points[15].y + points[0].y) / 2))
        for index in 0 ..< 16 {
            path.addArc(
                tangent1End: points[index],
                tangent2End: points[(index + 1) % 16],
                radius: radius * (index.isMultiple(of: 2) ? 0.16 : 0.12),
            )
        }
        path.closeSubpath()
        return path
    }

    private struct Ring {
        /// As a fraction of the seal's radius.
        var radius: CGFloat
        /// Where the gap is, in radians: one of the eight directions the badge's points face.
        var gapAngle: CGFloat
        /// How wide the gap is, in radians: 60°, 90° or 120°.
        var gapWidth: CGFloat
    }

    /// The outer ring from the digest's second and fourth bytes, the inner one from its third and fifth.
    private var rings: [Ring] {
        [ring(radius: 0.52, byte: 1), ring(radius: 0.30, byte: 2)]
    }

    private func ring(radius: CGFloat, byte: Int) -> Ring {
        let digest = seal.digest
        let direction = CGFloat(digest[byte] % 8)
        let width = CGFloat(2 + Int(digest[byte + 2] % 3))
        return Ring(radius: radius, gapAngle: -.pi / 2 + direction * .pi / 4, gapWidth: width * .pi / 6)
    }

    /// Apple's system colors in their light appearance, but yellow, which white can't be read on.
    private static let palette: [(CGFloat, CGFloat, CGFloat)] = [
        (0.0, 0.478, 1.0), // blue
        (0.345, 0.337, 0.839), // indigo
        (0.686, 0.322, 0.871), // purple
        (1.0, 0.176, 0.333), // pink
        (1.0, 0.231, 0.188), // red
        (1.0, 0.584, 0.0), // orange
        (0.204, 0.780, 0.349), // green
        (0.0, 0.780, 0.745), // mint
        (0.188, 0.690, 0.780), // teal
        (0.635, 0.518, 0.369), // brown
        (0.557, 0.557, 0.576), // gray
    ]
}
