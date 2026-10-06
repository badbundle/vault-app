import SwiftUI
import VaultFeed

/// What the main window shows: the vault once it's unlocked, and before that, whatever has to come first.
///
/// In order: the failure screen if the vault couldn't be opened, an erase the app was stopped in the middle of
/// finishing, the first launch while there's no App Lock Password, and the lock screen while Vault is locked. Nothing
/// from the vault shows until every one of those is past.
struct VaultMacRootView: View {
    @State private var appLock = VaultMacRoot.appLockService
    @State private var interruptedErase = VaultMacRoot.interruptedErase

    var body: some View {
        Group {
            if let failure = VaultMacRoot.vaultStoreLoadFailure, VaultMacRoot.missingVault?.state != .erased {
                VaultMacStoreFailureView(failure: failure, missingVault: VaultMacRoot.missingVault)
            } else if let interruptedErase, interruptedErase.state != .erased {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !appLock.isPasswordSet {
                VaultMacFirstLaunchView(
                    appLock: appLock,
                    canAuthenticate: VaultMacRoot.deviceAuthenticationService.canAuthenticate,
                )
            } else if case let .locked(locked) = appLock.state {
                VaultMacLockView(
                    state: locked,
                    unlock: { await appLock.unlock() },
                    unlockWithPassword: { await appLock.unlock(password: $0) },
                )
            } else {
                VaultMacMainView(
                    feed: VaultMacRoot.feedModel,
                    localSettings: VaultMacRoot.localSettings,
                    authentication: VaultMacRoot.deviceAuthenticationService,
                    keyDeriverFactory: VaultMacRoot.vaultKeyDeriverFactory,
                )
                .environment(\.vaultMacItemPreviews, .live)
                .environment(\.vaultMacCopy, VaultMacCopyAction { action in
                    await VaultMacCopier(
                        pasteboard: VaultMacRoot.pasteboard,
                        authentication: VaultMacRoot.deviceAuthenticationService,
                    ).copy(action)
                })
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
