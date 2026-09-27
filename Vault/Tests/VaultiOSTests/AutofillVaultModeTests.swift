import Foundation
import Testing
import VaultFeed
import VaultiOSShared
@testable import VaultiOS

/// How the AutoFill extension finds the vault for each request, from the storage state as it is then.
struct AutofillVaultModeTests {
    @Test
    func plainVault_isPlain() {
        #expect(AutofillVaultMode(state: .plain) == .plain)
    }

    /// Once the conversion has committed, the vault opens with the password, whatever the app still has to tidy up.
    @Test(arguments: [
        nil,
        VaultStorageState.Transition.deletingPlainStore(archives: []),
        .clearingSystemSurfaces,
    ] as [VaultStorageState.Transition?])
    func encryptedVault_isEncrypted(transition: VaultStorageState.Transition?) {
        let state = VaultStorageState(mode: .password, transition: transition)

        #expect(AutofillVaultMode(state: state) == .encrypted)
    }

    /// Mid-conversion the plain store may already be out of date, and there's no encrypted vault to open yet.
    @Test
    func vaultBeingConverted_isUnavailable() {
        #expect(AutofillVaultMode(state: VaultStorageState(mode: .plain, transition: .encrypting)) == .unavailable)
    }

    /// Nothing may open while an erase or a rekey is underway, even with the right password.
    @Test(arguments: [
        VaultStorageState.Transition.erasing,
        .turningOff,
        .turningOn,
    ])
    func vaultBeingErasedOrRekeyed_isUnavailable(transition: VaultStorageState.Transition) {
        #expect(AutofillVaultMode(state: VaultStorageState(mode: .password, transition: transition)) == .unavailable)
    }

    /// With the password turned off, the extension can't open the vault until VAULT-50 gives it the device key: every
    /// surface stays locked meanwhile.
    @Test(arguments: [nil, VaultStorageState.Transition.turningOn] as [VaultStorageState.Transition?])
    func passwordTurnedOff_isUnavailable(transition: VaultStorageState.Transition?) {
        #expect(AutofillVaultMode(state: VaultStorageState(mode: .deviceKey, transition: transition)) == .unavailable)
    }

    @Test
    func unreadableState_isUnavailable() {
        #expect(AutofillVaultMode(state: nil) == .unavailable)
    }
}

/// What the app does with a link from a widget.
struct WidgetDeepLinkActionTests {
    @Test
    func incrementHOTP_plainVault_isFollowed() {
        #expect(WidgetDeepLink.Action.incrementHOTP(itemID: UUID()).isAllowed(isVaultPlain: true))
    }

    /// A widget never offers it while the vault is encrypted, and a link left from before doesn't either.
    @Test
    func incrementHOTP_encryptedVault_isIgnored() {
        #expect(!WidgetDeepLink.Action.incrementHOTP(itemID: UUID()).isAllowed(isVaultPlain: false))
    }

    /// Opening an item still waits for the app to be unlocked, with the password, like anything else.
    @Test(arguments: [true, false])
    func openItemDetail_isFollowed(isVaultPlain: Bool) {
        #expect(WidgetDeepLink.Action.openItemDetail(itemID: UUID()).isAllowed(isVaultPlain: isVaultPlain))
    }
}
