import Foundation
import SwiftUI
import VaultFeed

/// Form row saying whether a backup password is set and, if known, when.
///
/// Shows nothing while the status is unknown: guessing either way would be misleading.
struct BackupPasswordStatusRow: View {
    var status: VaultDataModel.BackupPasswordStatus

    var body: some View {
        if let content {
            FormRow(image: Image(systemName: content.systemImage), color: content.color) {
                TextAndSubtitle(title: content.title, subtitle: content.subtitle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(content.title))
            .accessibilityValue(Text(content.subtitle ?? ""))
        }
    }

    private struct Content {
        var title: String
        var subtitle: String?
        var systemImage: String
        var color: Color
    }

    private var content: Content? {
        switch status {
        case .unknown:
            nil
        case .notSet:
            Content(
                title: "No Backup Password",
                subtitle: "You need one to export your vault or turn on auto-backup.",
                systemImage: "exclamationmark.shield.fill",
                color: .orange,
            )
        case let .set(metadata):
            Content(
                title: "Backup Password Set",
                subtitle: metadata.lastSetDate.map {
                    "Last set \($0.formatted(date: .abbreviated, time: .shortened))"
                },
                systemImage: "checkmark.shield.fill",
                color: .green,
            )
        }
    }
}

#Preview {
    Form {
        BackupPasswordStatusRow(status: .set(.init(lastSetDate: Date())))
        BackupPasswordStatusRow(status: .set(.init(lastSetDate: nil)))
        BackupPasswordStatusRow(status: .notSet)
        BackupPasswordStatusRow(status: .unknown)
    }
}
