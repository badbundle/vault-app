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
        #expect(query[kSecAttrService as String] as? String == VaultIdentifiers.SecureStorageKey.vaultDeviceKey)
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
        let attributes = VaultDeviceKeychainStore.attributes(for: SymmetricKey(size: .bits256))

        let accessible = attributes[kSecAttrAccessible as String] as? String
        #expect(accessible == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    @Test
    func attributes_holdTheKey() throws {
        let key = SymmetricKey(size: .bits256)

        let attributes = VaultDeviceKeychainStore.attributes(for: key)

        let data = try #require(attributes[kSecValueData as String] as? Data)
        #expect(data == key.withUnsafeBytes { Data($0) })
        #expect(data.count == 32)
    }
}
