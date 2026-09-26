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
    func delay_isImmediatelyByDefault() throws {
        let sut = try AppLockSettingsStore(userDefaults: .nonPersistent())

        #expect(sut.delay == .immediately)
    }

    @Test(arguments: AppLockDelay.allCases)
    func delay_persistsInTheDefaults(delay: AppLockDelay) throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let sut = AppLockSettingsStore(userDefaults: userDefaults)

        sut.delay = delay

        #expect(AppLockSettingsStore(userDefaults: userDefaults).delay == delay)
        #expect(userDefaults.integer(forKey: "vault.preferences.app-lock.delay") == delay.rawValue)
    }

    @Test
    func delay_unknownValue_isImmediately() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        userDefaults.set(42, forKey: "vault.preferences.app-lock.delay")

        #expect(AppLockSettingsStore(userDefaults: userDefaults).delay == .immediately)
    }

    @Test
    func isEnabled_usesTheAppLockKey() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let sut = AppLockSettingsStore(userDefaults: userDefaults)

        sut.isEnabled = true

        #expect(userDefaults.bool(forKey: "vault.preferences.app-lock.is-enabled"))
    }
}
