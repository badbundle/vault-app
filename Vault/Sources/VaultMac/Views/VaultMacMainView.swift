import SwiftUI
import VaultFeed
import VaultSettings

/// The main window, once Vault is unlocked: the sidebar, the list of items with their live codes, and the open item's
/// page, as Apple's Passwords app lays out the Mac's (docs/mac-app.md, decision 6).
struct VaultMacMainView: View {
    @State private var feed: VaultMacFeedModel
    var localSettings: LocalSettings
    var authentication: DeviceAuthenticationService
    var keyDeriverFactory: any VaultKeyDeriverFactory

    /// Goes up each time Find (⌘F) asks for the search field.
    @State private var searchFocusRequest = 0
    /// The Backups page that's open, while Backups is chosen in the sidebar.
    @State private var backupsPage: VaultMacBackupsPage?
    private var backupServices: VaultMacBackupServices {
        .live
    }

    /// The item editor that's open, if one is.
    @State private var editorRequest: VaultMacEditorRequest?
    /// The item that's asking whether to delete it, if one is.
    @State private var pendingDeletion: VaultItem.Metadata?
    @State private var deletionProblem: String?
    @Environment(\.vaultMacItemPreviews) private var previews
    @Environment(\.vaultMacCopy) private var copy

    init(
        feed: VaultMacFeedModel,
        localSettings: LocalSettings,
        authentication: DeviceAuthenticationService,
        keyDeriverFactory: any VaultKeyDeriverFactory,
    ) {
        _feed = State(initialValue: feed)
        self.localSettings = localSettings
        self.authentication = authentication
        self.keyDeriverFactory = keyDeriverFactory
    }

    private var dataModel: VaultDataModel {
        feed.dataModel
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } content: {
            if feed.showsItems {
                list
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            } else {
                VaultMacBackupsList(selection: $backupsPage, services: backupServices)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            }
        } detail: {
            if !feed.showsItems {
                VaultMacBackupsDetail(page: backupsPage, services: backupServices)
            } else if let item = feed.selectedItem {
                VaultMacItemDetailView(
                    item: item,
                    tags: dataModel.allTags.filter { item.metadata.tags.contains($0.id) },
                    authentication: authentication,
                    keyDeriverFactory: keyDeriverFactory,
                )
                .id(item.id)
            } else {
                ContentUnavailableView("No Item Selected", systemImage: "key.horizontal")
            }
        }
        .task {
            await feed.load()
        }
        .onChange(of: dataModel.itemsSearchQuery) {
            Task { await feed.reloadItems() }
        }
        .onChange(of: dataModel.itemsFilteringByTags) {
            Task { await feed.reloadItems() }
        }
        .sheet(item: $editorRequest) { request in
            VaultMacEditorSheet(
                request: request,
                dataModel: dataModel,
                keyDeriverFactory: keyDeriverFactory,
                localSettings: localSettings,
                close: { editorRequest = nil },
            )
        }
        .environment(\.vaultMacEdit, openEditor)
        .environment(\.vaultMacDelete, VaultMacDeleteAction { pendingDeletion = $0 })
        // There's no undo and no history: once deleted, an item is gone (C6).
        .confirmationDialog(
            "Delete This Item?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: {
                if !$0 {
                    pendingDeletion = nil
                }
            }),
            presenting: pendingDeletion,
        ) { metadata in
            Button("Delete", role: .destructive) {
                Task { await delete(metadata) }
            }
        } message: { _ in
            Text("It's deleted from Vault at once, and can't be brought back.")
        }
        .alert(
            "Vault Couldn't Delete the Item",
            isPresented: Binding(get: { deletionProblem != nil }, set: {
                if !$0 {
                    deletionProblem = nil
                }
            }),
        ) {
            Button("OK") {}
        } message: {
            Text(deletionProblem ?? "")
        }
        .focusedSceneValue(\.vaultMacFindAction, VaultMacMenuAction { searchFocusRequest += 1 })
        .focusedSceneValue(\.vaultMacCopyCodeAction, copySelectedCode)
        .focusedSceneValue(\.vaultMacNewItemAction, editorRequest == nil ? openEditor : nil)
    }

    private var sidebar: some View {
        List(selection: $feed.sidebarSelection) {
            Section {
                Label("Items", systemImage: "key.horizontal.fill")
                    .tag(VaultMacSidebarItem.items)
                    .accessibilityIdentifier("sidebar.items")
            }
            if dataModel.allTags.isNotEmpty {
                Section("Tags") {
                    ForEach(dataModel.allTags) { tag in
                        Label(tag.name, systemImage: "tag.fill")
                            .tag(VaultMacSidebarItem.tag(tag.id))
                    }
                }
            }
            Section {
                Label("Backups", systemImage: "externaldrive.fill")
                    .tag(VaultMacSidebarItem.backups)
                    .accessibilityIdentifier("sidebar.backups")
            }
        }
        .listStyle(.sidebar)
    }

    private func delete(_ metadata: VaultItem.Metadata) async {
        do {
            try await dataModel.delete(itemID: metadata.id)
        } catch {
            deletionProblem = error.localizedDescription
        }
    }

    private var openEditor: VaultMacEditAction {
        VaultMacEditAction { request in
            editorRequest = request
        }
    }

    /// Copies the open item's code: Copy (⌘C) while no text has focus.
    private var copySelectedCode: VaultMacMenuAction? {
        guard feed.showsItems, let item = feed.selectedItem, let code = previews?.code(for: item),
              let action = code.pasteboardCopyText, let copy
        else { return nil }
        return VaultMacMenuAction {
            Task { _ = await copy(action) }
        }
    }

    private var list: some View {
        List(dataModel.items, selection: $feed.selectedItemID) { item in
            VaultMacItemRow(
                item: item,
                showsNextCode: localSettings.state.showsNextCode,
                copiesOnClick: localSettings.state.codeTapAction == .copy,
            )
            .tag(item.id)
        }
        .overlay {
            if dataModel.items.isEmpty {
                ContentUnavailableView(
                    dataModel.isSearching ? "No Results" : "No Items",
                    systemImage: dataModel.isSearching ? "magnifyingglass" : "key.horizontal",
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Code") { editorRequest = .newCode }
                    Button("New Note") { editorRequest = .newNote }
                    Button("New Recovery Phrase") { editorRequest = .newRecoveryPhrase }
                } label: {
                    Label("New Item", systemImage: "plus")
                }
                .help("New Item")
                .accessibilityIdentifier("feed.new-item")
            }
            ToolbarItem(placement: .automatic) {
                // A field of Vault's own rather than `searchable`'s, so it edits as every other field does (G52).
                VaultMacSearchField(text: Bindable(dataModel).itemsSearchQuery, focusRequest: searchFocusRequest)
                    .frame(width: 200)
            }
        }
        .accessibilityIdentifier("feed")
    }
}

extension FocusedValues {
    /// Focuses the main window's search field: Find (⌘F).
    @Entry var vaultMacFindAction: VaultMacMenuAction?
    /// Copies the open item's code: Copy (⌘C) while no text has focus.
    @Entry var vaultMacCopyCodeAction: VaultMacMenuAction?
}

/// Something a menu command does in the window that has focus.
@MainActor
struct VaultMacMenuAction {
    var perform: @MainActor () -> Void

    func callAsFunction() {
        perform()
    }
}
