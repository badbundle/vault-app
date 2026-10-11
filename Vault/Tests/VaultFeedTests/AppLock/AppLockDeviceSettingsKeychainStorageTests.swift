import Foundation
import Security
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check what
/// `AppLockDeviceSettingsKeychainStorage` would ask it for.
struct AppLockDeviceSettingsKeychainStorageTests {
    /// The AutoFill extension reads the same settings as the app.
    @Test
    func init_sharesTheItemWithTheExtensions() {
        let sut = AppLockDeviceSettingsKeychainStorage()

        #expect(sut.accessGroup == VaultSharedStorage.appGroupID)
    }

    @Test
    func itemQuery_matchesTheSettingsInTheAccessGroup() {
        let query = AppLockDeviceSettingsKeychainStorage.itemQuery(accessGroup: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        let service = query[kSecAttrService as String] as? String
        #expect(service == VaultIdentifiers.SecureStorageKey.appLockDeviceSettings.rawValue)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
    }

    /// On the Mac, the data protection keychain is the one that keeps an item to its access group, as iOS's does.
    @Test
    func itemQuery_usesTheDataProtectionKeychain() {
        let query = AppLockDeviceSettingsKeychainStorage.itemQuery(accessGroup: nil)

        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    /// Settings that synced to iCloud Keychain could be changed from another device.
    @Test
    func itemQuery_neverSyncs() {
        let query = AppLockDeviceSettingsKeychainStorage.itemQuery(accessGroup: nil)

        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    }

    /// Readable at a launch while the screen is locked, as the defaults are, but never moved to another device.
    @Test
    func attributes_keepTheItemOnThisDeviceOnceItsBeenUnlocked() throws {
        let attributes = try AppLockDeviceSettingsKeychainStorage.attributes(for: anySettings())

        let accessible = attributes[kSecAttrAccessible as String] as? String
        #expect(accessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test
    func attributes_holdTheSettings() throws {
        let settings = anySettings()

        let attributes = try AppLockDeviceSettingsKeychainStorage.attributes(for: settings)

        let data = try #require(attributes[kSecValueData as String] as? Data)
        #expect(try JSONDecoder().decode(AppLockDeviceSettings.self, from: data) == settings)
    }

    private func anySettings() -> AppLockDeviceSettings {
        AppLockDeviceSettings(erasesAfterFailedPasswords: true, delaySeconds: AppLockDelay.fiveMinutes.rawValue)
    }
}
