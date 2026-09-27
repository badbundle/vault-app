import Foundation
import Security
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check what
/// `VaultWrapStampKeychainStorage` would ask it for.
struct VaultWrapStampKeychainStorageTests {
    @Test
    func init_sharesTheItemWithTheExtensions() {
        let sut = VaultWrapStampKeychainStorage()

        #expect(sut.accessGroup == VaultSharedStorage.appGroupID)
    }

    @Test
    func itemQuery_matchesTheStampInTheAccessGroup() {
        let query = VaultWrapStampKeychainStorage.itemQuery(accessGroup: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == VaultIdentifiers.SecureStorageKey.vaultWrapStamp
            .rawValue)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
    }

    /// A stamp that synced from another device could be older than this device's wraps.
    @Test
    func itemQuery_neverSyncs() {
        let query = VaultWrapStampKeychainStorage.itemQuery(accessGroup: nil)

        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    }

    /// Restoring a backup can't put back an older stamp.
    @Test
    func attributes_keepTheItemOnThisDeviceWhileUnlocked() throws {
        let attributes = try VaultWrapStampKeychainStorage.attributes(for: 1_790_000_000_000)

        let accessible = attributes[kSecAttrAccessible as String] as? String
        #expect(accessible == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    @Test
    func attributes_holdTheStamp() throws {
        let attributes = try VaultWrapStampKeychainStorage.attributes(for: 1_790_000_000_000)

        let data = try #require(attributes[kSecValueData as String] as? Data)
        #expect(try JSONDecoder().decode(UInt64.self, from: data) == 1_790_000_000_000)
    }
}
