import SwiftUI
import VaultFeed

/// The words of a recovery phrase, numbered, in two columns: 1 to 12 down the first column and 13 to 24 down the
/// second, like the backup cards wallets provide.
///
/// The words are masked until revealed. Tapping any word reveals (or hides) them all at once.
struct RecoveryPhraseWordGridView: View {
    var words: [String]
    var isRevealed: Bool
    /// Positions of words to highlight as a warning, such as those that aren't in the wordlist.
    var highlightedPositions: Set<Int> = []
    var wordNumberLabel: (Int) -> String
    var toggleRevealed: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The same for every word, so the mask doesn't give away how long each one is.
    private static let mask = String(repeating: "•", count: 5)

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    private var rowCount: Int {
        (words.count + columnCount - 1) / columnCount
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0 ..< rowCount, id: \.self) { row in
                GridRow {
                    ForEach(0 ..< columnCount, id: \.self) { column in
                        let index = column * rowCount + row
                        if words.indices.contains(index) {
                            cell(index: index)
                        } else {
                            Color.clear
                                .gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
        // VoiceOver reads the words in order, rather than across the rows of the grid.
        .accessibilityElement(children: .contain)
    }

    private func cell(index: Int) -> some View {
        let isHighlighted = highlightedPositions.contains(index)
        return Button(action: toggleRevealed) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Sized to the widest number, so the words line up.
                ZStack(alignment: .trailing) {
                    Text(verbatim: "88")
                        .hidden()
                    Text(verbatim: "\(index + 1)")
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isHighlighted ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))

                Text(verbatim: isRevealed ? words[index] : Self.mask)
                    .font(.body.monospaced().weight(.medium))
                    .foregroundStyle(isRevealed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHighlighted ? AnyShapeStyle(Color.orange.opacity(0.2)) : AnyShapeStyle(.fill.quaternary),
                in: .rect(cornerRadius: 10),
            )
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(wordNumberLabel(index + 1)))
        .accessibilityValue(isRevealed ? Text(verbatim: words[index]) : Text("Hidden"))
        .accessibilityHint(isRevealed ? Text("Hides all the words") : Text("Reveals all the words"))
        .accessibilitySortPriority(Double(words.count - index))
    }
}

#Preview {
    @Previewable @State var isRevealed = false

    Form {
        RecoveryPhraseWordGridView(
            words: ["abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd"],
            isRevealed: isRevealed,
            highlightedPositions: [3],
            wordNumberLabel: { "Word \($0)" },
            toggleRevealed: { isRevealed.toggle() },
        )
    }
}
