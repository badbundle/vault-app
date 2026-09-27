import Foundation
import Testing
@testable import VaultFeed

/// How the extensions and QuickType find the vault, from the storage state as it is then.
struct VaultAccessModeTests {
    @Test
    func plainVault_isPlain() {
        #expect(VaultAccessMode(state: .plain) == .plain)
    }

    /// Once a conversion has committed, the vault opens with the password, whatever the app still has to tidy up.
    @Test(arguments: [
        nil,
        VaultStorageState.Transition.deletingPlainStore(archives: []),
        .deletingPlainStore(archives: ["archive"]),
        .clearingSystemSurfaces,
    ] as [VaultStorageState.Transition?])
    func passwordOn_needsThePassword(transition: VaultStorageState.Transition?) {
        let sut = VaultAccessMode(state: VaultStorageState(mode: .password, transition: transition))

        #expect(sut == .password)
        #expect(!sut.opensWithoutPassword)
    }

    /// With the password off, the device key opens the vault, and everything works as it does for a plain one, even
    /// while QuickType is still being filled again.
    @Test(arguments: [nil, VaultStorageState.Transition.syncingSystemSurfaces] as [VaultStorageState.Transition?])
    func passwordOff_opensWithTheDeviceKey(transition: VaultStorageState.Transition?) {
        let sut = VaultAccessMode(state: VaultStorageState(mode: .deviceKey, transition: transition))

        #expect(sut == .deviceKey)
        #expect(sut.opensWithoutPassword)
    }

    /// Mid-conversion the plain store may already be out of date, and there's no encrypted vault to open yet.
    @Test
    func vaultBeingConverted_isUnavailable() {
        #expect(VaultAccessMode(state: VaultStorageState(mode: .plain, transition: .encrypting)) == .unavailable)
    }

    /// Nothing may open while an erase or a rekey is underway, even with the right password or the device key.
    @Test(arguments: [
        VaultStorageState.Mode.password,
        .deviceKey,
    ], [
        VaultStorageState.Transition.erasing,
        .turningOff,
        .turningOn,
    ])
    func vaultBeingErasedOrRekeyed_isUnavailable(
        mode: VaultStorageState.Mode,
        transition: VaultStorageState.Transition,
    ) {
        #expect(VaultAccessMode(state: VaultStorageState(mode: mode, transition: transition)) == .unavailable)
    }

    @Test
    func unreadableState_isUnavailable() {
        #expect(VaultAccessMode(state: nil) == .unavailable)
        #expect(!VaultAccessMode.unavailable.opensWithoutPassword)
    }

    @Test
    func plain_opensWithoutPassword() {
        #expect(VaultAccessMode.plain.opensWithoutPassword)
    }
}
