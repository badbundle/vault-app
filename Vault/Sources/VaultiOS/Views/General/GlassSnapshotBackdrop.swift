import SwiftUI

extension EnvironmentValues {
    /// Draws a flat backdrop behind glass surfaces that opt in with
    /// `glassSnapshotBackdrop(in:)`.
    ///
    /// Only for snapshot tests: `CALayer.render(in:)` draws no glass at all,
    /// so without a backdrop a layout snapshot cannot show where a glass
    /// surface sits. The app leaves this off so the real material shows
    /// through, rather than a semi-opaque wash that defeats it.
    @Entry public var drawsGlassSnapshotBackdrop = false
}

extension View {
    /// Adds the snapshot-only backdrop behind a glass surface when
    /// `drawsGlassSnapshotBackdrop` is set, and does nothing otherwise.
    func glassSnapshotBackdrop(in shape: some Shape) -> some View {
        modifier(GlassSnapshotBackdropModifier(shape: shape))
    }
}

private struct GlassSnapshotBackdropModifier<S: Shape>: ViewModifier {
    var shape: S

    @Environment(\.drawsGlassSnapshotBackdrop) private var drawsBackdrop

    func body(content: Content) -> some View {
        if drawsBackdrop {
            content.background(Color(.systemBackground).opacity(0.85), in: shape)
        } else {
            content
        }
    }
}

/// Wraps another button style so the button can be hit anywhere within the
/// platform's default 44pt target, however small its bezel is drawn.
///
/// Padding or a content shape outside a `Button` does not grow its hit area,
/// so the margin around the bezel forwards taps to the button's action itself.
struct MinimumHitTargetButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    var base: Base

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(base)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
            .onTapGesture(perform: configuration.trigger)
    }
}
