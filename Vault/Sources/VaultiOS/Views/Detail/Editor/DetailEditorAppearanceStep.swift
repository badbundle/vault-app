import Foundation
import SwiftUI
import VaultFeed

/// The editor's appearance step, the same for every kind of item: a preview of the item, its color, and its tags.
struct DetailEditorAppearanceStep: View {
    /// Previews the item, so should have the color being chosen.
    var identity: DetailEditorItemIdentity
    @Binding var color: VaultItemColor?
    var selectedTags: [VaultItemTag]
    var remainingTags: [VaultItemTag]
    var tagCountDescription: String
    var addTag: (VaultItemTag) -> Void
    var removeTag: (VaultItemTag) -> Void

    @State private var isShowingTagPicker = false

    var body: some View {
        Section {
            DetailEditorItemBadge(identity: identity)
                .padding(.vertical, 4)
        }

        Section {
            ItemColorPicker(color: $color)
        } header: {
            Text("Color")
        }

        Section {
            Button {
                isShowingTagPicker = true
            } label: {
                VaultDetailTagsRow(tags: selectedTags, countDescription: tagCountDescription)
            }
        } footer: {
            Text("Tags group items together, so you can filter the vault by them.")
        }
        .sheet(isPresented: $isShowingTagPicker) {
            NavigationStack {
                VaultDetailTagEditView(
                    tagsThatAreSelected: selectedTags,
                    remainingTags: remainingTags,
                    didAdd: addTag,
                    didRemove: removeTag,
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            isShowingTagPicker = false
                        } label: {
                            Text("Done")
                        }
                    }
                }
            }
        }
    }
}
