import Foundation
import SwiftUI
import VaultFeed

struct VaultDetailTagEditView: View {
    var tagsThatAreSelected: [VaultItemTag]
    var remainingTags: [VaultItemTag]
    var didAdd: (VaultItemTag) -> Void
    var didRemove: (VaultItemTag) -> Void

    var body: some View {
        List {
            if hasAnyTags {
                currentTagsSection
            }
            remainingTagsSection
        }
        .navigationTitle(Text("Tags"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasAnyTags: Bool {
        !(tagsThatAreSelected.isEmpty && remainingTags.isEmpty)
    }

    private var currentTagsSection: some View {
        Section {
            ForEach(tagsThatAreSelected) { tag in
                Button {
                    withAnimation {
                        didRemove(tag)
                    }
                } label: {
                    tagRow(tag) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .id(tag.id)
            }

            if tagsThatAreSelected.isEmpty {
                PlaceholderView(
                    systemIcon: "tag.fill",
                    title: "No Tags Selected",
                    subtitle: "Add a tag from the available tags",
                )
                .frame(maxWidth: .infinity)
                .padding()
            }
        } header: {
            Text("Selected Tags")
        }
    }

    private var remainingTagsSection: some View {
        Section {
            ForEach(remainingTags) { tag in
                Button {
                    withAnimation {
                        didAdd(tag)
                    }
                } label: {
                    tagRow(tag) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .id(tag.id)
            }

            if remainingTags.isEmpty {
                PlaceholderView(
                    systemIcon: "checkmark.circle.fill",
                    title: "No Other Tags",
                    subtitle: "Create new tags in the tag manager",
                )
                .frame(maxWidth: .infinity)
                .padding()
            }
        } header: {
            Text("Available Tags")
        }
    }

    private func tagRow(_ tag: VaultItemTag, @ViewBuilder accessory: @escaping () -> some View) -> some View {
        HStack {
            TagRowLabel(tag: tag)
            Spacer()
            accessory()
        }
        .contentShape(Rectangle())
    }
}
