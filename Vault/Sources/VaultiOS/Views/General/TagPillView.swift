import Foundation
import SwiftUI
import VaultFeed

/// A tag as it appears throughout the app: its icon badge and name in a glass
/// capsule outlined in the tag's color.
///
/// The feed's filters, an item's tags and the tag editor's preview all draw a
/// tag with this one view, and the tag list uses the same badge and name, so a
/// tag looks the same wherever it appears. The environment's `controlSize`
/// picks the size: small and mini give a compact pill that sits level with
/// small capsule buttons.
struct TagPillView: View {
    var tag: VaultItemTag
    /// Tints the capsule with the tag's color, as for an active filter.
    var isSelected: Bool = false
    /// Whether the glass reacts to touch, for a pill that is itself a control.
    var isInteractive: Bool = false

    @Environment(\.controlSize) private var controlSize
    @ScaledMetric(relativeTo: .footnote) private var compactIconSize: Double = 20
    @ScaledMetric(relativeTo: .subheadline) private var regularIconSize: Double = 26

    private var isCompact: Bool {
        switch controlSize {
        case .mini, .small: true
        default: false
        }
    }

    /// The gap around the badge, the same on every side so the badge sits
    /// concentric with the capsule's leading end.
    private var iconInset: Double {
        isCompact ? 3 : 4
    }

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            TagIconView(
                iconName: tag.iconName,
                color: tag.color,
                size: isCompact ? compactIconSize : regularIconSize,
            )
            Text(tag.displayName)
                // The label color itself. `.primary` would take on a form
                // section header's gray, and glass draws it as a vibrant
                // fill that snapshot tests can't render in dark mode.
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(1)
        }
        .font(isCompact ? .footnote : .subheadline)
        .padding(iconInset)
        .padding(.trailing, isCompact ? 7 : 10)
        .background(
            Capsule(style: .circular)
                .fill(tag.fillColor(isSelected: isSelected))
                .stroke(tag.strokeColor, lineWidth: 1),
        )
        .glassEffect(.regular.interactive(isInteractive), in: .capsule)
        .glassSnapshotBackdrop(in: .capsule)
        .accessibilityElement(children: .combine)
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
