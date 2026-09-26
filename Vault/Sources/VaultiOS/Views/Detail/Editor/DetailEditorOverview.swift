import Foundation
import SwiftUI
import VaultFeed

/// Where editing an existing item starts: the item, then a card for each part of it that can be changed, with what
/// that part is set to now.
///
/// Opening a card goes straight to that step, so changing one thing doesn't mean going through the whole editor. The
/// cards are the new-item picker's, so the editor looks like the flow that made the item.
struct DetailEditorOverview: View {
    var kind: DetailEditorItemKind
    var identity: DetailEditorItemIdentity
    var steps: [DetailEditorStep]
    var summary: (DetailEditorStep) -> String
    var open: (DetailEditorStep) -> Void
    /// Shows the delete button, which calls this.
    var delete: (() -> Void)?

    var body: some View {
        DetailItemBadgeSection(identity: identity, footer: "Choose what to change.")

        ForEach(steps, id: \.self) { step in
            Section {
                Button {
                    open(step)
                } label: {
                    OptionCardLabel(
                        title: step.title(for: kind),
                        subtitle: subtitle(for: step),
                        systemImage: step.systemImage(for: kind),
                    )
                    .padding(.vertical, 6)
                }
            }
        }

        if let delete {
            Section {
                ProminentActionButton(
                    localized(key: "action.delete.title"),
                    systemImage: "trash.fill",
                    role: .destructive,
                ) {
                    delete()
                }
            }
        }
    }

    private func subtitle(for step: DetailEditorStep) -> String {
        let summary = summary(step)
        return summary.isNotBlank ? summary : step.subtitle(for: kind)
    }
}
