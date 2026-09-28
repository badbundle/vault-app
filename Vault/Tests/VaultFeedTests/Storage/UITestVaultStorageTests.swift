import Foundation
import Testing
@testable import VaultFeed

/// The UI tests' storage is only for a launch that asks for it with `-ui-test-vault`: without that, the vault's own
/// storage is used, as it always is in a release build, which doesn't have the UI tests' at all.
struct UITestVaultStorageTests {
    #if DEBUG
    @Test
    func current_withoutTheLaunchArgument_isNil() {
        #expect(UITestVaultStorage.current == nil)
    }
    #endif

    @Test(arguments: VaultIdentifiers.SecureStorageKey.allCases)
    func keychainService_withoutTheLaunchArgument_isTheKeysOwn(key: VaultIdentifiers.SecureStorageKey) {
        #expect(key.keychainService == key.rawValue)
    }
}
