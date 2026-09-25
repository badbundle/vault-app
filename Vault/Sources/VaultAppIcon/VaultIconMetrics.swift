import Foundation

/// The icon's geometry, as fractions of the canvas side.
///
/// Keeping everything relative lets the one drawing serve as a 1024 px App Store
/// icon and as a small in-app glyph without a second set of numbers. The defaults
/// trace the original hand-made icon.
public struct VaultIconMetrics: Sendable {
    /// Width (and height) of the door's outer edge.
    public var doorSide: CGFloat = 0.56
    /// Thickness of the door frame.
    public var doorStroke: CGFloat = 0.055
    /// Outer corner radius of the door.
    public var doorCornerRadius: CGFloat = 0.11
    /// Radius of the wheel's central hub.
    public var hubRadius: CGFloat = 0.085
    /// Radius of the hole through the hub.
    public var holeRadius: CGFloat = 0.030
    /// Thickness of each spoke.
    public var spokeThickness: CGFloat = 0.040
    /// Distance from the centre at which a spoke starts: inside the hub so the join
    /// is hidden, but outside the hole so it never crosses it.
    public var spokeInnerStart: CGFloat = 0.060
    /// Distance from the centre to the centre of each knob.
    public var spokeReach: CGFloat = 0.175
    /// Radius of the knob on the end of each spoke.
    public var knobRadius: CGFloat = 0.046
    /// Width of the rim-light stroke along the edges.
    public var highlightWidth: CGFloat = 0.008
    /// Degrees the door swings on its hinge when fully open (`doorOpening == 1`).
    public var doorOpenAngle: Double = 26

    public init() {}

    public static let standard = VaultIconMetrics()

    /// The same drawing with the door filling most of the canvas: for an in-app
    /// glyph the size of an SF Symbol, where the icon's generous margins would
    /// leave nothing visible.
    public static let compact = standard.scaled(by: 0.9 / standard.doorSide)

    /// Every length multiplied by `factor`, so the proportions are unchanged.
    public func scaled(by factor: CGFloat) -> VaultIconMetrics {
        var scaled = self
        scaled.doorSide *= factor
        scaled.doorStroke *= factor
        scaled.doorCornerRadius *= factor
        scaled.hubRadius *= factor
        scaled.holeRadius *= factor
        scaled.spokeThickness *= factor
        scaled.spokeInnerStart *= factor
        scaled.spokeReach *= factor
        scaled.knobRadius *= factor
        scaled.highlightWidth *= factor
        return scaled
    }
}
