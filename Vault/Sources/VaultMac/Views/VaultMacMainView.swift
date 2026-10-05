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

    @FocusState private var isSearchFocused: Bool
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
                ContentUnavailableView("Backups", systemImage: "externaldrive")
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            }
        } detail: {
            if feed.showsItems, let item = feed.selectedItem {
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
        .focusedSceneValue(\.vaultMacFindAction, VaultMacMenuAction { isSearchFocused = true })
        .focusedSceneValue(\.vaultMacCopyCodeAction, copySelectedCode)
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
        .searchable(text: Bindable(dataModel).itemsSearchQuery, placement: .toolbar, prompt: "Search")
        .searchFocused($isSearchFocused)
        .autocorrectionDisabled()
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
