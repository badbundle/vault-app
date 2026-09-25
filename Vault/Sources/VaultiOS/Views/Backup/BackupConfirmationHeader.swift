import Foundation
import SwiftUI

/// Centered confirmation that a backup step worked: a large symbol, a title and a subtitle.
///
/// Sits in its own `Form` section without a row background, so it reads as the screen's headline
/// rather than as another row. The symbol bounces once when the header first appears.
struct BackupConfirmationHeader: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var color: Color

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: Double = 72
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(color)
                .symbolEffect(.bounce, value: hasAppeared)
                .padding(.bottom, 4)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .noListBackground()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            hasAppeared = true
        }
    }
}

#Preview {
    Form {
        Section {
            BackupConfirmationHeader(
                title: "Backup Password Set",
                subtitle: "Your backups will be encrypted with this password from now on.",
                systemImage: "checkmark.shield.fill",
                color: .green,
            )
        }
    }
}
