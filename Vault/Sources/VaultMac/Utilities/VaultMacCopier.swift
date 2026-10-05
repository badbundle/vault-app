import Foundation
import VaultFeed

/// Copies an item's text, asking for Touch ID or the Mac's password first when the item is locked (G32).
@MainActor
struct VaultMacCopier {
    var pasteboard: VaultMacPasteboard
    var authentication: DeviceAuthenticationService

    /// Copies `action`'s text. Returns whether it did.
    @discardableResult
    func copy(_ action: VaultTextCopyAction) async -> Bool {
        if action.requiresAuthenticationToCopy {
            do {
                try await authentication.validateAuthentication(reason: "Copy the code")
            } catch {
                return false
            }
        }
        pasteboard.copy(action)
        return true
    }
}
