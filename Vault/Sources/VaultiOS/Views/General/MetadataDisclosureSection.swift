import SwiftUI
import VaultFeed

struct MetadataDisclosureSection: View {
    var tags: [VaultItemTag]
    var entries: [DetailEntry]
    @State private var isExpanded: Bool = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(entries) { entry in
                    LabeledContent {
                        Text(entry.detail)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(entry.title, systemImage: entry.systemIconName)
                    }
                }
            } label: {
                Label("Metadata", systemImage: "info.circle")
            }
        } footer: {
            tagsFooter
        }
    }

    @ViewBuilder
    private var tagsFooter: some View {
        if tags.isNotEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(tags) { tag in
                        TagPillView(tag: tag, isSelected: true)
                            .id(tag)
                    }
                }
                .controlSize(.small)
            }
            .scrollClipDisabled()
            .padding(.top, 8)
        }
    }
}
