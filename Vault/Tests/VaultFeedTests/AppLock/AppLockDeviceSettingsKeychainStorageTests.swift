import Foundation
import Security
import TestHelpers
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check what
/// `AppLockDeviceSettingsKeychainStorage` would ask it for, and run it on a keychain in memory.
struct AppLockDeviceSettingsKeychainStorageTests {
    /// The AutoFill extension reads the same settings as the app, and the widget extension can't (VAULT-129).
    @Test
    func init_sharesTheItemWithAutoFillOnly() {
        let sut = AppLockDeviceSettingsKeychainStorage()

        #expect(sut.item.accessGroup == VaultSharedStorage.keychainGroupID)
        #expect(sut.item.formerAccessGroup == VaultSharedStorage.appGroupID)
    }

    @Test
    func itemQuery_matchesTheSettingsInTheAccessGroup() {
        let query = AppLockDeviceSettingsKeychainStorage().item.query(in: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        let service = query[kSecAttrService as String] as? String
        #expect(service == VaultIdentifiers.SecureStorageKey.appLockDeviceSettings.rawValue)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
    }

    /// On the Mac, the data protection keychain is the one that keeps an item to its access group, as iOS's does.
    @Test
    func itemQuery_usesTheDataProtectionKeychain() {
        let query = AppLockDeviceSettingsKeychainStorage().item.query(in: nil)

        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    /// Settings that synced to iCloud Keychain could be changed from another device.
    @Test
    func itemQuery_neverSyncs() {
        let query = AppLockDeviceSettingsKeychainStorage().item.query(in: nil)

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

    // MARK: - In the keychain

    @Test
    func saveAndLoad_keepTheSettingsInTheSharedGroup() throws {
        let keychain = InMemoryKeychain()
        let sut = Self.storage(on: keychain)

        try sut.save(anySettings())

        #expect(try sut.load() == anySettings())
        #expect(keychain.item(.appLockDeviceSettings, in: VaultSharedStorage.appGroupID) == nil)
    }

    @Test
    func add_storesTheSettingsOnlyIfNoneAreStored() throws {
        let sut = Self.storage(on: InMemoryKeychain())
        let other = AppLockDeviceSettings(erasesAfterFailedPasswords: false, delaySeconds: 0)

        #expect(try sut.add(anySettings()) == true)
        #expect(try sut.add(other) == false)
        #expect(try sut.load() == anySettings())
    }

    /// Settings an earlier version kept in the App Group's access group are the Mac's settings until they're moved:
    /// they're never read from the defaults again.
    @Test
    func settingsStore_withTheSettingsStillInTheAppGroup_readsThemNotTheDefaults() throws {
        let keychain = InMemoryKeychain()
        try Self.putInTheAppGroup(anySettings(), on: keychain)
        let userDefaults = try UserDefaults.nonPersistent()
        userDefaults.set(false, forKey: VaultIdentifiers.Preferences.AppLock.erasesAfterFailedPasswords)
        let store = AppLockSettingsStore(userDefaults: userDefaults, deviceSettings: Self.storage(on: keychain))

        #expect(try store.loadErasesAfterFailedPasswords() == true)
        #expect(store.delay == .fiveMinutes)
        #expect(keychain.item(.appLockDeviceSettings, in: VaultSharedStorage.keychainGroupID) == nil)
    }

    @Test
    func moveFromTheAppGroup_keepsTheSettings() throws {
        let keychain = InMemoryKeychain()
        try Self.putInTheAppGroup(anySettings(), on: keychain)
        let sut = Self.storage(on: keychain)

        try sut.moveFromTheAppGroup()

        #expect(try sut.load() == anySettings())
        #expect(keychain.item(.appLockDeviceSettings, in: VaultSharedStorage.appGroupID) == nil)
        let moved = keychain.item(.appLockDeviceSettings, in: VaultSharedStorage.keychainGroupID)
        #expect(moved?.accessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    private static func storage(on keychain: InMemoryKeychain) -> AppLockDeviceSettingsKeychainStorage {
        AppLockDeviceSettingsKeychainStorage(item: SharedKeychainItem(key: .appLockDeviceSettings, keychain: keychain))
    }

    /// Puts `settings` where versions before VAULT-129 kept them.
    private static func putInTheAppGroup(_ settings: AppLockDeviceSettings, on keychain: InMemoryKeychain) throws {
        let attributes = try AppLockDeviceSettingsKeychainStorage.attributes(for: settings)
        let data = try #require(attributes[kSecValueData as String] as? Data)
        let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        keychain.set(
            .init(data: data, accessible: accessible),
            for: .appLockDeviceSettings,
            in: VaultSharedStorage.appGroupID,
        )
    }

    private func anySettings() -> AppLockDeviceSettings {
        AppLockDeviceSettings(erasesAfterFailedPasswords: true, delaySeconds: AppLockDelay.fiveMinutes.rawValue)
    }
}
