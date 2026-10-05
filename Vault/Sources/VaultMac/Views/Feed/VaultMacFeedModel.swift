import Foundation
import FoundationExtensions
import VaultFeed

/// What the main window shows: what's chosen in the sidebar, and the item whose page is open.
///
/// Searching and filtering are the shared `VaultDataModel`'s, exactly as on iOS: hidden items only appear while the
/// whole search is their passphrase (G8), and a killphrase deletes its item as soon as it's searched for, without
/// saying so (G1, G2).
@MainActor
@Observable
final class VaultMacFeedModel {
    let dataModel: VaultDataModel

    /// What's chosen in the sidebar. A tag filters the list to its items.
    var sidebarSelection: VaultMacSidebarItem? = .items {
        didSet {
            guard sidebarSelection != oldValue else { return }
            dataModel.itemsFilteringByTags = switch sidebarSelection {
            case let .tag(id): [id]
            case .items, .backups, nil: []
            }
        }
    }

    /// The item whose page is open, if it's still in the list.
    var selectedItemID: Identifier<VaultItem>?

    init(dataModel: VaultDataModel) {
        self.dataModel = dataModel
    }

    /// The open item, as the list has it now. `nil` once it's gone, as when a killphrase deletes it.
    var selectedItem: VaultItem? {
        guard let selectedItemID else { return nil }
        return dataModel.items.first { $0.id == selectedItemID }
    }

    /// Whether the list of items shows, rather than another page from the sidebar.
    var showsItems: Bool {
        switch sidebarSelection {
        case .items, .tag, nil: true
        case .backups: false
        }
    }

    /// Reads the vault as the window opens: first the keys that killphrases and search passphrases are checked with,
    /// as the iOS app's feed does, so searching fires a killphrase and finds a hidden item exactly as it does there
    /// (G1, G2, G8), then the tags and items.
    func load() async {
        await dataModel.setup()
        await dataModel.reloadData()
    }

    /// Reads the items again, for the search and tags as they are now.
    func reloadItems() async {
        await dataModel.reloadItems()
        // A page stays open only while its item is listed.
        if selectedItemID != nil, selectedItem == nil {
            selectedItemID = nil
        }
    }
}

/// What the main window's sidebar lists.
enum VaultMacSidebarItem: Hashable {
    case items
    case tag(Identifier<VaultItemTag>)
    case backups
}
