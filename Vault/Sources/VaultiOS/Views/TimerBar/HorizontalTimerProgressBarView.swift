import Combine
import SwiftUI

/// A progress bar: a track, filled from the leading edge by `fractionCompleted`.
///
/// When the environment has a `timerBarLabel`, the bar shows it at its leading edge, colored to contrast with
/// what's behind each part of it: muted text over the track, and `fillLabelColor` over the fill. The color
/// changes exactly where the fill ends, even as the fill animates across the label.
struct HorizontalTimerProgressBarView: View {
    var fractionCompleted: Double
    var color: Color
    var backgroundColor: Color = .init(.quaternarySystemFill)
    /// The label's color where it sits on the fill, which suits a saturated fill by default. (In dark mode with
    /// Increase Contrast it's black on any fill; see `labelColorOnFill`.)
    var fillLabelColor: Color = .white

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.timerBarLabel) private var label
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(backgroundColor)
                if let label {
                    LoadingBarLabel(text: label)
                        .foregroundStyle(Self.trackLabelColor)
                }
                Rectangle()
                    .fill(color)
                    .frame(width: isPlaceholder ? 0 : fractionCompleted * proxy.size.width)
                    .overlay(alignment: .leading) {
                        if let label {
                            // A second copy, laid out across the whole bar like the first, but only
                            // visible over the fill.
                            LoadingBarLabel(text: label)
                                .foregroundStyle(labelColorOnFill)
                                .frame(width: proxy.size.width, alignment: .leading)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipped()
            }
        }
    }

    /// Muted like secondary text, but stronger than `secondaryLabel`, which is only about 3:1 on the light track
    /// at this size. (Not the hierarchical `.secondary`: in a card that's a button, that would be the tint's.)
    private static let trackLabelColor = Color(.label).opacity(0.6)

    private var isPlaceholder: Bool {
        redactionReasons.contains(.placeholder)
    }

    /// Increase Contrast lightens the system's saturated colors in dark mode, where white on them drops to about
    /// 2:1, so the label turns black over the fill instead.
    private var labelColorOnFill: Color {
        if colorScheme == .dark, colorSchemeContrast == .increased {
            .black
        } else {
            fillLabelColor
        }
    }
}

extension HorizontalTimerProgressBarView {
    /// Just the track, for a bar with nothing to count down.
    static var empty: Self {
        .init(fractionCompleted: 0, color: .clear)
    }

    /// A bar filled with `color`, whose label is `labelColor`.
    static func filled(_ color: Color, labelColor: Color = .white) -> Self {
        .init(fractionCompleted: 1, color: color, fillLabelColor: labelColor)
    }

    /// The white bar a code card shows on its accent background while it's being edited.
    ///
    /// It stays out of the card's editing shimmer, so it's always solid white, and its label is the accent
    /// darkened to read on white: about 7.5:1, where the accent itself is only about 3.5:1.
    static var editing: Self {
        .filled(.white, labelColor: Color.accentColor.mix(with: .black, by: 0.3))
    }
}

#Preview("Example Views", traits: .sizeThatFitsLayout) {
    VStack {
        HorizontalTimerProgressBarView(
            fractionCompleted: 0.0,
            color: .blue,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.4,
            color: .blue,
        )
        .frame(width: 250, height: 20)
        .redacted(reason: .placeholder)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.4,
            color: .blue,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.6,
            color: .red,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.75,
            color: .yellow,
            backgroundColor: .yellow,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 1.0,
            color: .blue,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.1,
            color: .blue,
        )
        .frame(width: 250, height: 12)
        .clipShape(Capsule())
        .environment(\.timerBarLabel, "Code locked")
    }
}
