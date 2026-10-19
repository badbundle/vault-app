import SwiftUI
import VaultFeed
import VaultMacShared

extension VaultMacItemPreviews {
    /// The app's, from the shared repositories.
    static var live: VaultMacItemPreviews {
        VaultMacItemPreviews(
            totp: { VaultMacRoot.totpPreviewRepository.previewViewModel(metadata: $0, code: $1) },
            hotp: { VaultMacRoot.hotpPreviewRepository.previewViewModel(metadata: $0, code: $1) },
            timer: { VaultMacRoot.totpPreviewRepository.timerPeriodState(period: $0) },
            incrementer: { VaultMacRoot.hotpPreviewRepository.incrementerViewModel(id: $0, code: $1) },
        )
    }
}

extension EnvironmentValues {
    /// Copies an item's text: Vault's clipboard, after authenticating for a locked item.
    @Entry var vaultMacCopy: VaultMacCopyAction?
}

/// Copies an item's text, and says whether it did.
@MainActor
struct VaultMacCopyAction {
    var perform: @MainActor (VaultTextCopyAction) async -> Bool

    func callAsFunction(_ action: VaultTextCopyAction) async -> Bool {
        await perform(action)
    }
}
