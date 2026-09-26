import Foundation
import SwiftUI
import VaultFeed

/// The top of an editor step: how far through the editor it is, then the step's icon, title and what it's for.
///
/// Laid out like a row of the new-item picker, so each step reads as the next card in that flow.
struct DetailEditorStepHeader: View {
    var step: DetailEditorStep
    var kind: DetailEditorItemKind
    /// Where the step comes in a walkthrough, or `nil` when it was opened on its own.
    var position: Position?

    struct Position: Equatable {
        /// Counting from 1.
        var number: Int
        var count: Int
    }

    @ScaledMetric(relativeTo: .title2) private var iconSize: Double = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let position {
                DetailEditorProgressView(position: position)
            }

            HStack(alignment: .center, spacing: 14) {
                Image(systemName: step.systemImage(for: kind))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.accentColor, in: .rect(cornerRadius: 14))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title(for: kind))
                        .font(.title2.bold())
                        .foregroundStyle(Color(uiColor: .label))
                        .accessibilityAddTraits(.isHeader)
                    Text(step.subtitle(for: kind))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textCase(nil)
    }
}

/// A bar split into one segment per step, filled up to the current one.
private struct DetailEditorProgressView: View {
    var position: DetailEditorStepHeader.Position

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1 ... max(position.count, 1), id: \.self) { number in
                Capsule()
                    .fill(number <= position.number ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(position.number) of \(position.count)")
    }
}

#Preview {
    Form {
        Section {
            DetailEditorStepHeader(step: .details, kind: .code, position: .init(number: 2, count: 4))
        }
        .listRowBackground(Color.clear)
    }
}
