import Foundation
import SwiftUI
import VaultFeed

/// A tag's badge and name, laid out as a list row.
///
/// The same badge and name as `TagPillView`, spaced like a `FormRow` so a
/// list of tags lines up with the app's other forms.
struct TagRowLabel: View {
    var tag: VaultItemTag

    @ScaledMetric(relativeTo: .body) private var iconSize: Double = 28

    var body: some View {
        HStack(spacing: 16) {
            TagIconView(iconName: tag.iconName, color: tag.color, size: iconSize)
            Text(tag.displayName)
                .foregroundStyle(Color.primary)
        }
    }
}
