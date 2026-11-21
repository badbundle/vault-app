import CoreGraphics
import Foundation

/// The picture of a `BackupSeal`: a disc of wax with a wavy edge, two rings, and two white guilloche rosettes pressed
/// into it, as on a banknote.
///
/// Every part comes from the seal's digest: the wax's color, the number of waves in its edge, and each rosette's
/// lobes, ripple and twist. So two seals look different at a glance, and the same seal looks the same everywhere it's
/// drawn: on a PDF backup, and on screen on iOS and the Mac. Which byte drives what never changes, as printed seals
/// have to keep matching.
public struct BackupSealArtwork: Sendable {
    public let seal: BackupSeal

    public init(seal: BackupSeal) {
        self.seal = seal
    }

    /// The wax's color, in sRGB.
    public var waxColor: CGColor {
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
        // Line widths were chosen at a radius of 120 points, and scale with the seal.
        let scale = radius / 120
        let samples = max(240, min(900, Int(radius * 8)))

        context.saveGState()
        defer { context.restoreGState() }

        context.addPath(edge(center: center, radius: radius, samples: samples))
        context.setFillColor(waxColor)
        context.fillPath()

        let rim = lightened(waxColor, by: 0.55).copy(alpha: 0.8) ?? waxColor
        context.setStrokeColor(rim)
        for (fraction, width) in [(0.84, 2.5), (0.80, 1.0)] {
            let ring = radius * fraction
            context.setLineWidth(width * scale)
            context.strokeEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2))
        }

        context.setLineWidth(scale)
        context.setLineJoin(.round)
        let layers: [(Rosette, CGFloat)] = [
            (Rosette(digest: seal.digest, offset: 4, base: 0.60, strands: 22), 0.55),
            (Rosette(digest: seal.digest, offset: 10, base: 0.30, strands: 14), 0.8),
        ]
        for (rosette, alpha) in layers {
            for path in rosette.paths(center: center, radius: radius, samples: samples) {
                context.addPath(path)
            }
            context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
            context.strokePath()
        }
    }

    /// The wax's outline: a circle with waves around it, and a slower wobble so no two edges are alike.
    private func edge(center: CGPoint, radius: CGFloat, samples: Int) -> CGPath {
        let digest = seal.digest
        let waves = CGFloat(16 + Int(digest[1] % 8))
        let wobble = CGFloat(3 + Int(digest[2] % 3))
        let wobblePhase = CGFloat(digest[3]) / 40
        let path = CGMutablePath()
        for step in 0 ... samples {
            let angle = CGFloat(step) / CGFloat(samples) * 2 * .pi
            let distance = radius * (0.97 + 0.03 * sin(waves * angle) + 0.012 * sin(wobble * angle + wobblePhase))
            let point = CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func lightened(_ color: CGColor, by fraction: CGFloat) -> CGColor {
        let components = color.components ?? [0, 0, 0, 1]
        let mixed = components.prefix(3).map { $0 + (1 - $0) * fraction }
        return CGColor(srgbRed: mixed[0], green: mixed[1], blue: mixed[2], alpha: 1)
    }

    /// Wax colors, spread around the color wheel and dark enough for white lines on them.
    private static let palette: [(CGFloat, CGFloat, CGFloat)] = [
        (0.72, 0.11, 0.16), (0.80, 0.33, 0.10), (0.72, 0.53, 0.08), (0.20, 0.45, 0.18),
        (0.04, 0.47, 0.45), (0.10, 0.45, 0.70), (0.12, 0.22, 0.52), (0.33, 0.20, 0.62),
        (0.53, 0.16, 0.55), (0.70, 0.15, 0.42), (0.42, 0.24, 0.15), (0.27, 0.31, 0.38),
    ]
}

/// A band of closed curves around the center, each a circle with two ripples on it, turned a little from the last:
/// the guilloche pattern.
private struct Rosette {
    var lobes: CGFloat
    var ripple: CGFloat
    var lobeDepth: CGFloat
    var rippleDepth: CGFloat
    var twist: CGFloat
    var base: CGFloat
    var strands: Int

    init(digest: [UInt8], offset: Int, base: CGFloat, strands: Int) {
        lobes = CGFloat(5 + Int(digest[offset] % 8))
        ripple = CGFloat(2 + Int(digest[offset + 1] % 4))
        lobeDepth = 0.07 + CGFloat(digest[offset + 2]) / 255 * 0.05
        rippleDepth = 0.02 + CGFloat(digest[offset + 3]) / 255 * 0.03
        twist = CGFloat(digest[offset + 4]) / 255 * 2 * .pi
        self.base = base
        self.strands = strands
    }

    func paths(center: CGPoint, radius: CGFloat, samples: Int) -> [CGPath] {
        (0 ..< strands).map { strand in
            let phase = CGFloat(strand) / CGFloat(strands) * 2 * .pi / lobes + twist
            let path = CGMutablePath()
            for step in 0 ... samples {
                let angle = CGFloat(step) / CGFloat(samples) * 2 * .pi
                let distance = radius * (
                    base + lobeDepth * sin(lobes * angle + phase) + rippleDepth * sin(ripple * angle - 2 * phase)
                )
                let point = CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            return path
        }
    }
}
