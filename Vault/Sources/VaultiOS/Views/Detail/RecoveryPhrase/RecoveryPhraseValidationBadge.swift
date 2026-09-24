import SwiftUI
import VaultFeed

/// Whether a recovery phrase's words and checksum are valid.
struct RecoveryPhraseValidationBadge: View {
    var summary: RecoveryPhraseValidationSummary

    var body: some View {
        // Not a `Label`: at accessibility sizes it lets the title wrap underneath the icon.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: summary.systemIconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(summary.detail)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        switch summary.kind {
        case .valid: .green
        case .warning: .orange
        case .neutral: .secondary
        }
    }
}
