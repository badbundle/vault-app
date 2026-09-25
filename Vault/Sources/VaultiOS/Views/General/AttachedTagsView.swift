import Foundation
import SwiftUI
import VaultFeed

/// The tags attached to an item, as compact glass pills that wrap onto as
/// many lines as they need, so none are hidden off the edge.
///
/// The pills are plain, never tinted: the tint marks an active filter in the
/// feed, and an item's tags aren't a selection.
struct AttachedTagsView: View {
    var tags: [VaultItemTag]

    var body: some View {
        WrappingLayout(spacing: 8) {
            ForEach(tags) { tag in
                TagPillView(tag: tag)
            }
        }
        .controlSize(.small)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    AttachedTagsView(tags: [
        .init(id: .init(), name: "Work", color: .init(color: .blue), iconName: "briefcase.fill"),
        .init(id: .init(), name: "Personal", color: .init(color: .green), iconName: "person.fill"),
        .init(id: .init(), name: "Finance", color: .init(color: .orange), iconName: "creditcard.fill"),
        .init(id: .init(), name: "Travel", color: .init(color: .purple), iconName: "airplane"),
    ])
    .frame(width: 240)
    .padding()
}
