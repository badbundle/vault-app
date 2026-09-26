import Foundation
import SwiftUI
import VaultFeed

/// A row of colors to choose an item's color from, ending in a well for any other color.
struct ItemColorPicker: View {
    /// `nil` is the default color.
    @Binding var color: VaultItemColor?

    @ScaledMetric(relativeTo: .body) private var swatchSize: Double = 36

    /// The system colors as they are in light mode, so an item keeps the same color whatever the appearance.
    static let palette: [(name: String, color: VaultItemColor)] = [
        ("Gray", .default),
        ("Red", .init(red: 1, green: 0.22, blue: 0.24)),
        ("Orange", .init(red: 1, green: 0.55, blue: 0.16)),
        ("Yellow", .init(red: 1, green: 0.8, blue: 0)),
        ("Green", .init(red: 0.2, green: 0.78, blue: 0.35)),
        ("Mint", .init(red: 0, green: 0.78, blue: 0.75)),
        ("Cyan", .init(red: 0, green: 0.75, blue: 0.95)),
        ("Blue", .init(red: 0, green: 0.53, blue: 1)),
        ("Indigo", .init(red: 0.38, green: 0.33, blue: 0.96)),
        ("Purple", .init(red: 0.8, green: 0.4, blue: 0.95)),
        ("Pink", .init(red: 1, green: 0.18, blue: 0.47)),
        ("Brown", .init(red: 0.67, green: 0.52, blue: 0.37)),
    ]

    private var currentColor: VaultItemColor {
        color ?? .default
    }

    private var isCustomColor: Bool {
        !Self.palette.contains { $0.color == currentColor }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchSize), spacing: 12)], spacing: 12) {
            ForEach(Self.palette, id: \.name) { swatch in
                Button {
                    color = swatch.color
                } label: {
                    swatchView(swatch.color.color, isSelected: swatch.color == currentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(swatch.color == currentColor ? .isSelected : [])
            }

            customColorWell
        }
        .padding(.vertical, 6)
    }

    private func swatchView(_ fill: Color, isSelected: Bool) -> some View {
        Circle()
            .fill(fill.gradient)
            .frame(width: swatchSize, height: swatchSize)
            .padding(3)
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
            }
            .contentShape(.circle)
    }

    /// Any other color, drawn as a rainbow ring until one is chosen.
    private var customColorWell: some View {
        ColorPicker(selection: customColorBinding, supportsOpacity: false) {
            EmptyView()
        }
        .labelsHidden()
        .frame(width: swatchSize + 6, height: swatchSize + 6)
        .overlay {
            if isCustomColor {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Other Color")
        .accessibilityAddTraits(isCustomColor ? .isSelected : [])
    }

    private var customColorBinding: Binding<Color> {
        Binding {
            currentColor.color
        } set: { newValue in
            color = VaultItemColor(color: newValue)
        }
    }
}

#Preview {
    @Previewable @State var color: VaultItemColor?
    Form {
        ItemColorPicker(color: $color)
    }
}
