import Foundation
import SwiftUI
import VaultFeed

/// What an item looks like, for its editor: its symbol, color and name.
struct DetailEditorItemIdentity {
    var systemImage: String
    var title: String
    var subtitle: String?
    var color: VaultItemColor?
}

/// An item's symbol on a square of its color, with its name beside it.
///
/// Heads the editor's overview so it's clear which item is being changed, and previews the item in the appearance
/// step as its color changes.
struct DetailEditorItemBadge: View {
    var identity: DetailEditorItemIdentity

    @ScaledMetric(relativeTo: .title) private var badgeSize: Double = 64

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: identity.systemImage)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(
                    (identity.color ?? .default).color.gradient,
                    in: .rect(cornerRadius: badgeSize * 0.28, style: .continuous),
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.title)
                    .font(.title3.bold())
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(2)
                if let subtitle = identity.subtitle, subtitle.isNotBlank {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    DetailEditorItemBadge(identity: .init(
        systemImage: "key.horizontal.fill",
        title: "GitHub",
        subtitle: "bradley@example.com",
        color: .init(red: 0.55, green: 0.36, blue: 0.96),
    ))
    .padding()
}
