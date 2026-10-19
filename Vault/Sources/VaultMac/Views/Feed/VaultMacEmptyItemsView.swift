import SwiftUI

/// What the list shows while it has no items, or none that a search finds.
///
/// For a vault with no items at all, it offers each kind of new item, in the order of the New Item menu, so the first
/// thing a new person sees points at recovery phrases and private keys. Choosing one opens that item's editor.
struct VaultMacEmptyItemsView: View {
    var isSearching: Bool
    /// Whether the vault has no items at all, so the list offers to add one.
    var offersNewItems: Bool
    var open: (VaultMacEditorRequest) -> Void

    var body: some View {
        if isSearching {
            ContentUnavailableView("No Results", systemImage: "magnifyingglass")
        } else if offersNewItems {
            ContentUnavailableView {
                Label("No Items", systemImage: "key.horizontal")
            } description: {
                Text("Add an item to get started.")
            } actions: {
                // One above another: side by side, they're wider than the list.
                VStack(spacing: 8) {
                    VaultMacNewItemButtons(open: open)
                }
                .fixedSize()
            }
        } else {
            ContentUnavailableView("No Items", systemImage: "key.horizontal")
        }
    }
}

/// A button for each kind of new item, in the order every add flow offers them: recovery phrases and private keys
/// first, then notes, then codes. The New Item menu and the empty list show them, and the File menu lists them in the
/// same order.
struct VaultMacNewItemButtons: View {
    var open: (VaultMacEditorRequest) -> Void

    var body: some View {
        Button("New Recovery Phrase") { open(.newRecoveryPhrase) }
        Button("New Private Key") { open(.newPrivateKey) }
        Button("New Note") { open(.newNote) }
        Button("New Code") { open(.newCode) }
    }
}
