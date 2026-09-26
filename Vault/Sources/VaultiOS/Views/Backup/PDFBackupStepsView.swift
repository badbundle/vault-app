import Foundation
import SwiftUI

/// The two steps of a PDF backup, create then save, so it's clear from the start that making the PDF
/// isn't the end of it.
struct PDFBackupStepsView: View {
    enum Progress {
        /// Nothing done yet: creating the PDF is next.
        case creating
        /// The PDF exists but hasn't been saved anywhere.
        case saving
        /// The PDF has been saved at least once.
        case done
    }

    var progress: Progress

    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: Double = 24

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                createStep
                connector
                saveStep
            }
            VStack(alignment: .leading, spacing: 8) {
                createStep
                saveStep
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var createStep: some View {
        step(number: 1, title: "Create PDF", state: progress == .creating ? .current : .done)
    }

    private var saveStep: some View {
        let state: StepState = switch progress {
        case .creating: .upcoming
        case .saving: .current
        case .done: .done
        }
        return step(number: 2, title: "Save or Print", state: state)
    }

    private var connector: some View {
        Capsule()
            .fill(progress == .creating ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.green))
            .frame(width: 24, height: 2)
            .accessibilityHidden(true)
    }

    private enum StepState {
        case upcoming, current, done
    }

    private func step(number: Int, title: String, state: StepState) -> some View {
        HStack(spacing: 6) {
            badge(number: number, state: state)
            Text(title)
                .fontWeight(state == .current ? .semibold : .regular)
                .foregroundStyle(state == .upcoming ? .secondary : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(number), \(title)"))
        .accessibilityValue(Text(accessibilityValue(for: state)))
    }

    @ViewBuilder
    private func badge(number: Int, state: StepState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .foregroundStyle(.white, .green)
                .frame(width: badgeSize, height: badgeSize)
        case .current:
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(Color.accentColor, in: .circle)
        case .upcoming:
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: badgeSize, height: badgeSize)
                .overlay(Circle().strokeBorder(.tertiary, lineWidth: 1.5))
        }
    }

    private func accessibilityValue(for state: StepState) -> String {
        switch state {
        case .upcoming: "Not started"
        case .current: "Current step"
        case .done: "Done"
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        PDFBackupStepsView(progress: .creating)
        PDFBackupStepsView(progress: .saving)
        PDFBackupStepsView(progress: .done)
    }
}
