import Foundation
import SwiftUI
import VaultFeed

/// A running auto-backup in detail: how far it has got, every step it takes, what started it and
/// where it's saving to.
struct AutoBackupProgressView: View {
    var run: AutoBackupRun
    /// The folder the backup is saved to, already quoted for use in a sentence.
    var destinationName: String

    @ScaledMetric(relativeTo: .body) private var stepIconSize: Double = 20

    private typealias Phase = AutoBackupProgress.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
            steps
            details
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
        .accessibilityValue(Text(percentage))
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.progress.phase.localizedTitle)
                    .font(.headline)
                Spacer()
                Text(percentage)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            ProgressView(value: run.progress.fractionCompleted)
            Text("Step \(run.progress.phase.stepNumber) of \(Phase.allCases.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .animation(.linear(duration: 0.2), value: run.progress.fractionCompleted)
    }

    private var percentage: String {
        run.progress.fractionCompleted.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Steps

    private enum StepState {
        case done, current, upcoming
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Phase.allCases, id: \.self) { phase in
                stepRow(phase, state: state(of: phase))
            }
        }
    }

    private func state(of phase: Phase) -> StepState {
        if phase.stepNumber < run.progress.phase.stepNumber {
            .done
        } else if phase == run.progress.phase {
            .current
        } else {
            .upcoming
        }
    }

    private func stepRow(_ phase: Phase, state: StepState) -> some View {
        HStack(spacing: 10) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .current:
                    ProgressView()
                        .controlSize(.small)
                case .upcoming:
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: stepIconSize, height: stepIconSize)

            Text(phase.stepTitle)
                .font(.subheadline.weight(state == .current ? .semibold : .regular))
                .foregroundStyle(state == .upcoming ? .secondary : .primary)
        }
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(startedDescription, systemImage: "clock")
            Label("Saving to \(destinationName)", systemImage: "folder")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .labelStyle(DetailLabelStyle(iconWidth: stepIconSize))
    }

    private var startedDescription: String {
        let time = run.startedAt.formatted(date: .omitted, time: .shortened)
        return switch run.trigger {
        case .automatic: "Started automatically at \(time)"
        case .manual: "Started with Back Up Now at \(time)"
        }
    }

    private var accessibilityDescription: String {
        [
            "Backing up",
            "Step \(run.progress.phase.stepNumber) of \(Phase.allCases.count): \(run.progress.phase.stepTitle)",
            startedDescription,
            "Saving to \(destinationName)",
        ].joined(separator: ". ")
    }
}

/// Lines the detail icons up with the step icons above them.
private struct DetailLabelStyle: LabelStyle {
    var iconWidth: Double

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon
                .frame(width: iconWidth)
            configuration.title
        }
    }
}

#Preview {
    Form {
        AutoBackupProgressView(
            run: .init(
                trigger: .automatic,
                startedAt: Date(),
                progress: .init(phase: .rendering, phaseFraction: 0.4),
            ),
            destinationName: "“Vault Backups”",
        )
    }
}
