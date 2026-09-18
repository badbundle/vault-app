import Foundation
import SwiftUI
import VaultFeed

struct TagPillView: View {
    var tag: VaultItemTag
    var isSelected: Bool = false

    @Environment(\.controlSize) private var controlSize

    /// Small controls get tighter insets so a row of pills sits level with
    /// small capsule buttons.
    private var isCompact: Bool {
        switch controlSize {
        case .mini, .small: true
        default: false
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 8 : 12) {
            TagIconView(iconName: tag.iconName)
            Text(tag.name.isBlank ? "Tag" : tag.name)
        }
        .padding(.horizontal, isCompact ? 10 : 12)
        .padding(.vertical, isCompact ? 5 : 8)
        .background(
            Capsule(style: .circular)
                .fill(tag.fillColor(isSelected: isSelected))
                .stroke(tag.strokeColor(isSelected: isSelected), lineWidth: 1),
        )
        .foregroundStyle(tag.strokeColor(isSelected: isSelected))
    }
}

#Preview("Not selected", traits: .sizeThatFitsLayout) {
    VStack {
        TagPillView(
            tag: .init(id: .init(), name: "Tag", color: .init(color: .blue), iconName: "tag.fill"),
            isSelected: false,
        )
        TagPillView(
            tag: .init(id: .init(), name: "Tag", color: .init(color: .white), iconName: "tag.fill"),
            isSelected: false,
        )
        TagPillView(
            tag: .init(id: .init(), name: "Tag", color: .init(color: .black), iconName: "tag.fill"),
            isSelected: false,
        )
    }
}

#Preview("Selected", traits: .sizeThatFitsLayout) {
    VStack {
        TagPillView(
            tag: .init(id: .init(), name: "Tag", color: .init(color: .blue), iconName: "tag.fill"),
            isSelected: true,
        )
        TagPillView(
            tag: .init(id: .init(), name: "Tag", color: .init(color: .white), iconName: "tag.fill"),
            isSelected: true,
        )
        TagPillView(
            tag: .init(id: .init(), name: "Tag", color: .init(color: .black), iconName: "tag.fill"),
            isSelected: true,
        )
    }
}
