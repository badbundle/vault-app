import SwiftUI
import VaultFeed

/// The words of a recovery phrase, numbered, in two columns: 1 to 12 down the first column and 13 to 24 down the
/// second, like the backup cards wallets provide.
struct RecoveryPhraseWordGridView: View {
    var words: [String]
    var wordNumberLabel: (Int) -> String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Sized to the widest number, so the words line up.
            ZStack(alignment: .trailing) {
                Text(verbatim: "88")
                    .hidden()
                Text(verbatim: "\(index + 1)")
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)

            Text(verbatim: words[index])
                .font(.body.monospaced().weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(wordNumberLabel(index + 1)))
        .accessibilityValue(Text(verbatim: words[index]))
        .accessibilitySortPriority(Double(words.count - index))
    }
}

#Preview {
    Form {
        RecoveryPhraseWordGridView(
            words: ["abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd"],
            wordNumberLabel: { "Word \($0)" },
        )
    }
}
