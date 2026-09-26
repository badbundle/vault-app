import SwiftUI

/// The wheel handle on the door, in turned metal: a hub with a hole through it,
/// four spokes at 45° and a knob on the end of each.
///
/// Each part is lit on its own so the wheel reads as solid: the spokes are
/// cylinders lit from above, and the hub and knobs are domes lit from the top left,
/// streaked by the lathe that turned them, with a rim that catches the light above
/// and falls into shade below. The parts turn with `rotation` but the light stays
/// where it is, as it would on a real wheel.
struct VaultWheelView: View {
    var rotation: Angle
    var metal: VaultAppIconPalette.Metal
    var metrics: VaultIconMetrics
    /// Side of the square the metrics are fractions of.
    var side: CGFloat

    var body: some View {
        ZStack {
            // Spokes first, so their ends tuck under the knobs and the hub.
            ForEach(0 ..< 4, id: \.self) { arm in
                spoke(at: angle(of: arm))
            }
            ForEach(0 ..< 4, id: \.self) { arm in
                knob(at: angle(of: arm))
            }
            hub
        }
        .frame(width: side, height: side)
    }

    private func angle(of arm: Int) -> Angle {
        .degrees(45 + 90 * Double(arm)) + rotation
    }

    /// The point `distance` (a fraction of `side`) out from the centre along `angle`.
    private func point(at angle: Angle, distance: CGFloat) -> CGPoint {
        CGPoint(
            x: side * (0.5 + cos(angle.radians) * distance),
            y: side * (0.5 + sin(angle.radians) * distance),
        )
    }

    /// Starts inside the hub, so the join is hidden, but outside the hole, so it
    /// never crosses it, and ends in the middle of its knob.
    private func spoke(at angle: Angle) -> some View {
        let inner = metrics.spokeInnerStart
        let outer = metrics.spokeReach
        return Capsule()
            .fill(metal.cylinderGradient)
            .frame(width: (outer - inner) * side, height: metrics.spokeThickness * side)
            .rotationEffect(angle.keepingTopEdgeUp)
            .position(point(at: angle, distance: (inner + outer) / 2))
    }

    private func knob(at angle: Angle) -> some View {
        turnedFace(Circle(), diameter: metrics.knobRadius * 2 * side)
            .position(point(at: angle, distance: metrics.spokeReach))
    }

    private var hub: some View {
        let diameter = metrics.hubRadius * 2 * side
        let hole = metrics.holeRadius * 2 * side
        let rim = metrics.wheelRimWidth * side
        return ZStack {
            turnedFace(Circle().subtracting(Circle().inset(by: (diameter - hole) / 2)), diameter: diameter)
            Circle()
                .strokeBorder(metal.boreGradient, lineWidth: rim)
                .frame(width: hole + rim * 2, height: hole + rim * 2)
        }
        .position(x: side / 2, y: side / 2)
    }

    /// A round part `diameter` across, turned on a lathe.
    private func turnedFace(_ face: some Shape, diameter: CGFloat) -> some View {
        ZStack {
            face.fill(metal.domeGradient(radius: diameter / 2))
            face.fill(metal.turnedStreaks)
            Circle().strokeBorder(metal.rimGradient, lineWidth: metrics.wheelRimWidth * side)
        }
        .frame(width: diameter, height: diameter)
    }
}

extension Angle {
    /// This angle or the one half a turn round, whichever keeps the top edge of a
    /// shape rotated by it facing up. A capsule looks the same either way round,
    /// but its cylinder gradient is lit along its top edge.
    fileprivate var keepingTopEdgeUp: Angle {
        let turned = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return .degrees(turned > 90 && turned <= 270 ? turned - 180 : turned)
    }
}
