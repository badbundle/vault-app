import CryptoKit
import Foundation
import Security
import Testing
import VaultCore
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check what `VaultDeviceKeychainStore` would
/// ask it for.
struct VaultDeviceKeychainStoreTests {
    @Test
    func init_sharesTheItemWithTheExtensions() {
        let sut = VaultDeviceKeychainStore()

        #expect(sut.accessGroup == VaultSharedStorage.appGroupID)
    }

    @Test
    func itemQuery_matchesTheDeviceKeyInTheAccessGroup() {
        let query = VaultDeviceKeychainStore.itemQuery(accessGroup: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == VaultIdentifiers.SecureStorageKey.vaultDeviceKey
            .rawValue)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
    }

    /// Synced to iCloud Keychain, it would open the vault's file on any of the user's devices.
    @Test
    func itemQuery_neverSyncs() {
        let query = VaultDeviceKeychainStore.itemQuery(accessGroup: nil)

        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    }

    /// Readable while the device is locked after its first unlock, so the widgets can refresh, and restored with a
    /// backup, like the file it opens.
    @Test
    func attributes_makeTheKeyReadableAfterTheFirstUnlock() {
        let attributes = VaultDeviceKeychainStore.attributes(for: Data(count: 32))

        let accessible = attributes[kSecAttrAccessible as String] as? String
        #expect(accessible == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    @Test
    func attributes_holdTheKey() throws {
        let keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }

        let attributes = VaultDeviceKeychainStore.attributes(for: keyData)

        #expect(attributes[kSecValueData as String] as? Data == keyData)
    }
}
