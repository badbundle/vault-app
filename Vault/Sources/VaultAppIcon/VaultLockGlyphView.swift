import SwiftUI

/// The safe door and its wheel, with no background.
///
/// One drawing serves both the app icon (wheel at rest, door shut) and every frame
/// of the lock animation (wheel spinning, door swinging on its left-hand hinge).
/// The depth comes from layering alone: a metal gradient and a rim light clipped
/// to the edges. No blur, shadow or material effects, so it renders the same on
/// screen, in `ImageRenderer` and in snapshots.
public struct VaultLockGlyphView: View {
    public var wheelRotation: Angle
    /// 0 is shut; 1 is swung open by `metrics.doorOpenAngle`.
    public var doorOpening: Double
    public var palette: VaultAppIconPalette
    public var metrics: VaultIconMetrics

    public init(
        wheelRotation: Angle = .zero,
        doorOpening: Double = 0,
        appearance: VaultAppIconAppearance = .light,
        metrics: VaultIconMetrics = .standard,
    ) {
        self.init(wheelRotation: wheelRotation, doorOpening: doorOpening, palette: appearance.palette, metrics: metrics)
    }

    /// Drawn in colors of its own rather than one of the icon's appearances, such
    /// as `.monochrome(.white)` on a colored background.
    public init(
        wheelRotation: Angle = .zero,
        doorOpening: Double = 0,
        palette: VaultAppIconPalette,
        metrics: VaultIconMetrics = .standard,
    ) {
        self.wheelRotation = wheelRotation
        self.doorOpening = doorOpening
        self.palette = palette
        self.metrics = metrics
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            artwork(side: side)
                .frame(width: side, height: side)
                .rotation3DEffect(
                    .degrees(-doorOpening * metrics.doorOpenAngle),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: UnitPoint(x: (1 - metrics.doorSide) / 2, y: 0.5),
                    perspective: 0.5,
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func artwork(side: CGFloat) -> some View {
        let door = VaultDoorShape(metrics: metrics)
        // Rotating the shape rather than the view keeps the light coming from
        // above while the wheel turns.
        let wheel = VaultWheelShape(metrics: metrics).rotation(wheelRotation)
        let highlightWidth = side * metrics.highlightWidth

        return ZStack {
            door.fill(palette.metalGradient)
            door
                .stroke(palette.highlightGradient, lineWidth: highlightWidth)
                .clipShape(door)
            wheel.fill(palette.metalGradient)
            wheel
                .stroke(palette.highlightGradient, lineWidth: highlightWidth)
                .clipShape(wheel)
        }
    }
}

#Preview("Closed") {
    VaultLockGlyphView()
        .frame(width: 256, height: 256)
}

#Preview("Open, dark") {
    VaultLockGlyphView(wheelRotation: .degrees(30), doorOpening: 1, appearance: .dark)
        .frame(width: 256, height: 256)
        .background(Color.black)
}
