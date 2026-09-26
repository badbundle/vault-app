import Foundation
import VaultFeed
import VaultSettings

/// What tapping a card in the feed does, and what its menu offers.
///
/// Out of edit mode, tapping a code copies it or shows its details, as the "Tap a Code To" setting says, and the
/// code's menu offers both, so the other is a touch and hold away. Anything that can't be copied, such as a note,
/// opens when tapped and has no menu. In edit mode, tapping opens any item to edit and there's no menu.
///
/// Copying a locked item asks the user to authenticate first, whether it's from a tap or the menu.
@MainActor
struct VaultItemTapHandler {
    var previewActionHandler: any VaultItemPreviewActionHandler
    var authenticationService: DeviceAuthenticationService
    var copy: (VaultTextCopyAction) -> Void
    var showDetails: (Identifier<VaultItem>) -> Void

    /// Taps the item with the given `id`.
    ///
    /// - Throws: If authentication couldn't be done, in which case nothing happens.
    func tap(_ id: Identifier<VaultItem>, isEditing: Bool, codeTapAction: CodeTapAction) async throws {
        guard !isEditing else {
            showDetails(id)
            return
        }
        switch previewActionHandler.previewActionForVaultItem(id: id) {
        case let .copyText(copyAction):
            switch codeTapAction {
            case .copy:
                try await copyAfterAuthenticating(copyAction)
            case .showDetails:
                showDetails(id)
            }
        case let .openItemDetail(detailID):
            showDetails(detailID)
        case nil:
            break
        }
    }

    /// What the menu of the item with the given `id` offers: copying and showing the details of a code, and nothing
    /// for anything else, or in edit mode.
    func menuActions(for id: Identifier<VaultItem>, isEditing: Bool) -> [VaultItemMenuAction] {
        guard !isEditing, case .copyText = previewActionHandler.previewActionForVaultItem(id: id) else {
            return []
        }
        return [.copy, .showDetails]
    }

    /// Does what the item's menu offered.
    ///
    /// The text to copy is worked out now, rather than when the menu opened, so a code that has moved on since is
    /// copied as it is now.
    ///
    /// - Throws: If authentication couldn't be done, in which case nothing happens.
    func perform(_ action: VaultItemMenuAction, on id: Identifier<VaultItem>) async throws {
        switch action {
        case .copy:
            guard case let .copyText(copyAction) = previewActionHandler.previewActionForVaultItem(id: id) else {
                return
            }
            try await copyAfterAuthenticating(copyAction)
        case .showDetails:
            showDetails(id)
        }
    }

    private func copyAfterAuthenticating(_ copyAction: VaultTextCopyAction) async throws {
        if copyAction.requiresAuthenticationToCopy {
            let result = try await authenticationService.authenticate(reason: "Authenticate to copy locked data")
            guard result == .success(.authenticated) else { return }
        }
        copy(copyAction)
    }
}

/// Something a code's menu in the feed offers.
enum VaultItemMenuAction: Equatable, Hashable, CaseIterable {
    case copy
    case showDetails

    var title: String {
        switch self {
        case .copy: "Copy Code"
        case .showDetails: "Show Details"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: "doc.on.doc"
        case .showDetails: "info.circle"
        }
    }
}
