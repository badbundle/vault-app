import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

struct AppLockSettingsStoreTests {
    @Test
    func isEnabled_isOffByDefault() throws {
        let sut = try AppLockSettingsStore(userDefaults: .nonPersistent())

        #expect(!sut.isEnabled)
    }

    @Test
    func isEnabled_persistsInTheDefaults() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let sut = AppLockSettingsStore(userDefaults: userDefaults)

        sut.isEnabled = true

        // Another process, such as an extension, reads the same defaults.
        #expect(AppLockSettingsStore(userDefaults: userDefaults).isEnabled)

        sut.isEnabled = false

        #expect(!AppLockSettingsStore(userDefaults: userDefaults).isEnabled)
    }

    @Test
    func isEnabled_usesTheAppLockKey() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let sut = AppLockSettingsStore(userDefaults: userDefaults)

        sut.isEnabled = true

        #expect(userDefaults.bool(forKey: "vault.preferences.app-lock.is-enabled"))
    }
}
