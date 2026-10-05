import SwiftUI

/// The main window: the sidebar, and what's selected in it.
struct VaultMacMainView: View {
    @State private var selection: VaultMacSidebarItem? = .items

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Items", systemImage: "key.horizontal.fill")
                        .tag(VaultMacSidebarItem.items)
                        .accessibilityIdentifier("sidebar.items")
                }
                Section {
                    Label("Backups", systemImage: "externaldrive.fill")
                        .tag(VaultMacSidebarItem.backups)
                        .accessibilityIdentifier("sidebar.backups")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .items, nil:
                ContentUnavailableView("No Items", systemImage: "key.horizontal")
            case .backups:
                ContentUnavailableView("Backups", systemImage: "externaldrive")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

/// What the main window's sidebar lists.
enum VaultMacSidebarItem: Hashable {
    case items
    case backups
}
