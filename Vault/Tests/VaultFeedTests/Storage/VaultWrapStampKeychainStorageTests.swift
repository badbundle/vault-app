import Foundation
import Security
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check what
/// `VaultWrapStampKeychainStorage` would ask it for, and run it on a keychain in memory.
struct VaultWrapStampKeychainStorageTests {
    /// The AutoFill extension stamps the vaults it opens too, and the widget extension can't read it (VAULT-129).
    @Test
    func init_sharesTheItemWithAutoFillOnly() {
        let sut = VaultWrapStampKeychainStorage()

        #expect(sut.item.accessGroup == VaultSharedStorage.keychainGroupID)
        #expect(sut.item.formerAccessGroup == VaultSharedStorage.appGroupID)
    }

    @Test
    func itemQuery_matchesTheStampInTheAccessGroup() {
        let query = VaultWrapStampKeychainStorage().item.query(in: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == VaultIdentifiers.SecureStorageKey.vaultWrapStamp
            .rawValue)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
    }

    /// A stamp that synced from another device could be older than this device's wraps.
    @Test
    func itemQuery_neverSyncs() {
        let query = VaultWrapStampKeychainStorage().item.query(in: nil)

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

    // MARK: - In the keychain

    @Test
    func saveAndLoad_keepTheStampInTheSharedGroup() throws {
        let keychain = InMemoryKeychain()
        let sut = Self.storage(on: keychain)

        try sut.save(1_790_000_000_000)

        #expect(try sut.load() == 1_790_000_000_000)
        #expect(keychain.item(.vaultWrapStamp, in: VaultSharedStorage.appGroupID) == nil)
    }

    /// A stamp an earlier version kept in the App Group's access group is still followed until it's moved, so later
    /// wraps are still later than it.
    @Test
    func stamper_withTheStampStillInTheAppGroup_stampsAfterIt() throws {
        let keychain = InMemoryKeychain()
        try Self.putInTheAppGroup(1_790_000_000_000, on: keychain)
        let stamper = VaultDeviceWrapStamper(storage: Self.storage(on: keychain), currentDate: { .distantPast })

        let stamp = try stamper.nextWrapStamp(rewrapping: .distantPast)

        #expect(stamp == Date(timeIntervalSince1970: 1_790_000_000.001))
    }

    @Test
    func moveFromTheAppGroup_keepsTheStamp() throws {
        let keychain = InMemoryKeychain()
        try Self.putInTheAppGroup(1_790_000_000_000, on: keychain)
        let sut = Self.storage(on: keychain)

        try sut.moveFromTheAppGroup()

        #expect(try sut.load() == 1_790_000_000_000)
        #expect(keychain.item(.vaultWrapStamp, in: VaultSharedStorage.appGroupID) == nil)
        let moved = keychain.item(.vaultWrapStamp, in: VaultSharedStorage.keychainGroupID)
        #expect(moved?.accessible == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    /// An erase deletes it wherever it is.
    @Test
    func remove_deletesTheStampFromBothGroups() throws {
        let keychain = InMemoryKeychain()
        let sut = Self.storage(on: keychain)
        try Self.putInTheAppGroup(1_790_000_000_000, on: keychain)
        try sut.save(1_790_000_000_001)

        try sut.remove()

        #expect(try sut.load() == nil)
        #expect(keychain.item(.vaultWrapStamp, in: VaultSharedStorage.appGroupID) == nil)
        #expect(keychain.item(.vaultWrapStamp, in: VaultSharedStorage.keychainGroupID) == nil)
    }

    private static func storage(on keychain: InMemoryKeychain) -> VaultWrapStampKeychainStorage {
        VaultWrapStampKeychainStorage(item: SharedKeychainItem(key: .vaultWrapStamp, keychain: keychain))
    }

    /// Puts `stamp` where versions before VAULT-129 kept it.
    private static func putInTheAppGroup(_ stamp: UInt64, on keychain: InMemoryKeychain) throws {
        let data = try #require(VaultWrapStampKeychainStorage.attributes(for: stamp)[kSecValueData as String] as? Data)
        keychain.set(.init(data: data), for: .vaultWrapStamp, in: VaultSharedStorage.appGroupID)
    }
}
