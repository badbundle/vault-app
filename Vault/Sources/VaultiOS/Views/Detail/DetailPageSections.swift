import Foundation
import SwiftUI
import VaultFeed

/// The top of an item's page, viewing or editing: the item's badge, with an optional line beneath it.
///
/// Viewing starts with it just as the editor's overview does, laid out the same, so switching between them with Edit
/// and Done leaves the item where it is and only the cards beneath it change.
struct DetailItemBadgeSection: View {
    var identity: DetailEditorItemIdentity
    var footer: String?

    var body: some View {
        Section {
            DetailEditorItemBadge(identity: identity)
        } footer: {
            if let footer {
                Text(footer)
                    .padding(.top, 8)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
    }
}

/// The heading of a card on an item's page: an icon on a square and a title, like the cards of the editor's overview,
/// with what the item has beneath the title.
struct DetailPageCardLabel<Detail: View>: View {
    var title: String
    var systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        // Top-aligned, so a long detail runs on down the card rather than pushing the icon to its middle. With one line
        // of detail the icon and text are the same height, and sit as they do on the overview's cards.
        HStack(alignment: .top, spacing: 14) {
            OptionCardIcon(systemImage: systemImage, color: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .label))
                detail()
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}

extension DetailPageCardLabel where Detail == DetailPageCardSubtitle {
    init(title: String, subtitle: String, systemImage: String, tint: Color = .accentColor) {
        self.init(title: title, systemImage: systemImage, tint: tint) {
            DetailPageCardSubtitle(text: subtitle)
        }
    }
}

/// A line under a card's title, styled like the subtitles of the editor overview's cards.
struct DetailPageCardSubtitle: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            // Explicit, so a button or disclosure group in a list doesn't tint it.
            .foregroundStyle(Color(uiColor: .secondaryLabel))
    }
}

/// What an item says about itself, in its own words.
struct DetailPageDescriptionSection: View {
    var title: String
    var text: String

    var body: some View {
        Section {
            DetailPageCardLabel(title: title, systemImage: "text.quote") {
                Text(text)
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .label))
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }
        }
    }
}

/// The last cards on an item's page: the tags it's filed under, then the details kept about it, which open when
/// they're wanted.
struct DetailPageInfoSections: View {
    var tags: [VaultItemTag]
    var entries: [DetailEntry]

    @State private var isShowingDetails: Bool

    init(tags: [VaultItemTag], entries: [DetailEntry], isShowingDetails: Bool = false) {
        self.tags = tags
        self.entries = entries
        _isShowingDetails = State(initialValue: isShowingDetails)
    }

    var body: some View {
        if tags.isNotEmpty {
            Section {
                DetailPageCardLabel(title: "Tags", systemImage: "tag.fill") {
                    AttachedTagsView(tags: tags)
                        .padding(.top, 6)
                }
            }
        }

        if entries.isNotEmpty {
            Section {
                DisclosureGroup(isExpanded: $isShowingDetails) {
                    ForEach(entries) { entry in
                        LabeledContent {
                            Text(entry.detail)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label(entry.title, systemImage: entry.systemIconName)
                        }
                    }
                } label: {
                    DetailPageCardLabel(title: "Details", systemImage: "info") {
                        // What's inside, rather than any of it, so it doesn't repeat a row once they're showing.
                        DetailPageCardSubtitle(text: entries.map(\.title).joined(separator: " · "))
                            .lineLimit(1)
                    }
                }
                .disclosureGroupStyle(DetailPageDisclosureStyle())
            }
        }
    }
}

/// Opens and closes a card with the chevron of the editor overview's cards, turning down when it's open.
///
/// The list's own disclosure style draws a heavier chevron in the text color.
private struct DetailPageDisclosureStyle: DisclosureGroupStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy) {
                configuration.isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isExpanded ? Text("Expanded") : Text("Collapsed"))

        if configuration.isExpanded {
            configuration.content
        }
    }
}
