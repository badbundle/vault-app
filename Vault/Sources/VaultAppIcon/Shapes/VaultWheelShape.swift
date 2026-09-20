import SwiftUI

/// The wheel handle: a hub with a hole through it, four spokes at 45° and a knob on
/// the end of each.
public struct VaultWheelShape: Shape {
    public var metrics: VaultIconMetrics

    public init(metrics: VaultIconMetrics = .standard) {
        self.metrics = metrics
    }

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let thickness = metrics.spokeThickness * side
        let spokeStart = metrics.spokeInnerStart * side
        let reach = metrics.spokeReach * side

        // One arm is drawn along the +x axis from the origin and then rotated and
        // moved into place four times, so the arms are guaranteed identical.
        let spoke = Path(
            roundedRect: CGRect(
                x: spokeStart,
                y: -thickness / 2,
                width: reach - spokeStart,
                height: thickness,
            ),
            cornerRadius: thickness / 2,
        )
        let knob = Path(ellipseIn: CGRect(center: CGPoint(x: reach, y: 0), radius: metrics.knobRadius * side))

        var wheel = Path(ellipseIn: CGRect(center: centre, radius: metrics.hubRadius * side))
        for arm in 0 ..< 4 {
            let angle = Angle.degrees(45 + 90 * Double(arm))
            let transform = CGAffineTransform(translationX: centre.x, y: centre.y)
                .rotated(by: angle.radians)
            wheel = wheel
                .union(spoke.applying(transform))
                .union(knob.applying(transform))
        }
        return wheel.subtracting(Path(ellipseIn: CGRect(center: centre, radius: metrics.holeRadius * side)))
    }
}

extension CGRect {
    /// A square centred on `center` reaching `radius` in every direction.
    fileprivate init(center: CGPoint, radius: CGFloat) {
        self.init(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
