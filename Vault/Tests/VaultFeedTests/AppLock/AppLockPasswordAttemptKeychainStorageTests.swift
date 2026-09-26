import Foundation
import Security
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check what
/// `AppLockPasswordAttemptKeychainStorage` would ask it for.
struct AppLockPasswordAttemptKeychainStorageTests {
    @Test
    func init_sharesTheItemWithTheExtensions() {
        let sut = AppLockPasswordAttemptKeychainStorage()

        #expect(sut.accessGroup == VaultSharedStorage.appGroupID)
    }

    @Test
    func itemQuery_matchesTheAttemptRecordInTheAccessGroup() {
        let query = AppLockPasswordAttemptKeychainStorage.itemQuery(accessGroup: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        let service = query[kSecAttrService as String] as? String
        #expect(service == VaultIdentifiers.SecureStorageKey.appLockPasswordAttempts)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
    }

    /// A count that synced to iCloud Keychain could be reset from another device.
    @Test
    func itemQuery_neverSyncs() {
        let query = AppLockPasswordAttemptKeychainStorage.itemQuery(accessGroup: nil)

        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    }

    @Test
    func attributes_keepTheItemOnThisDeviceWhileUnlocked() throws {
        let attributes = try AppLockPasswordAttemptKeychainStorage.attributes(for: anyRecord())

        let accessible = attributes[kSecAttrAccessible as String] as? String
        #expect(accessible == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    @Test
    func attributes_holdTheRecord() throws {
        let record = anyRecord()

        let attributes = try AppLockPasswordAttemptKeychainStorage.attributes(for: record)

        let data = try #require(attributes[kSecValueData as String] as? Data)
        #expect(try JSONDecoder().decode(AppLockPasswordAttemptRecord.self, from: data) == record)
    }

    private func anyRecord() -> AppLockPasswordAttemptRecord {
        AppLockPasswordAttemptRecord(count: 7, latestAt: .now)
    }
}
