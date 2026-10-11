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

        try sut.setDelay(delay)

        #expect(AppLockSettingsStore(userDefaults: userDefaults).delay == delay)
        #expect(userDefaults.integer(forKey: Self.delayKey) == delay.rawValue)
    }

    @Test
    func delay_unknownValue_isImmediately() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        userDefaults.set(42, forKey: Self.delayKey)

        #expect(AppLockSettingsStore(userDefaults: userDefaults).delay == .immediately)
    }

    @Test
    func isEnabled_usesTheAppLockKey() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let sut = AppLockSettingsStore(userDefaults: userDefaults)

        sut.isEnabled = true

        #expect(userDefaults.bool(forKey: "vault.preferences.app-lock.is-enabled"))
    }

    @Test
    func erasesAfterFailedPasswords_isOffByDefault() throws {
        let sut = try AppLockSettingsStore(userDefaults: .nonPersistent())

        #expect(!sut.erasesAfterFailedPasswords)
        #expect(try !sut.loadErasesAfterFailedPasswords())
    }

    @Test
    func erasesAfterFailedPasswords_isOnlyStoredWhileItsOn() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let sut = AppLockSettingsStore(userDefaults: userDefaults)

        try sut.setErasesAfterFailedPasswords(true)

        #expect(AppLockSettingsStore(userDefaults: userDefaults).erasesAfterFailedPasswords)
        #expect(userDefaults.bool(forKey: Self.erasesKey))

        try sut.setErasesAfterFailedPasswords(false)

        #expect(!AppLockSettingsStore(userDefaults: userDefaults).erasesAfterFailedPasswords)
        #expect(userDefaults.object(forKey: Self.erasesKey) == nil)
    }

    // MARK: - Kept where only Vault can change them, as on the Mac

    @Test
    func deviceSettings_areOffAndImmediatelyByDefault() throws {
        let sut = try AppLockSettingsStore.keepingDeviceSettings()

        #expect(!sut.erasesAfterFailedPasswords)
        #expect(try !sut.loadErasesAfterFailedPasswords())
        #expect(sut.delay == .immediately)
    }

    /// Settings an earlier version kept in the defaults move into storage the first time they're read, and leave the
    /// defaults.
    @Test
    func deviceSettings_firstRead_moveWhatTheDefaultsHeld() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        userDefaults.set(true, forKey: Self.erasesKey)
        userDefaults.set(AppLockDelay.fiveMinutes.rawValue, forKey: Self.delayKey)
        let storage = InMemoryAppLockDeviceSettingsStorage()
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage, userDefaults: userDefaults)

        #expect(try sut.loadErasesAfterFailedPasswords())
        #expect(sut.delay == .fiveMinutes)
        #expect(storage.settings == AppLockDeviceSettings(erasesAfterFailedPasswords: true, delaySeconds: 300))
        #expect(userDefaults.object(forKey: Self.erasesKey) == nil)
        #expect(userDefaults.object(forKey: Self.delayKey) == nil)
    }

    /// With nothing to move, the defaults' own values are stored, so nothing put in the defaults later is ever moved.
    @Test
    func deviceSettings_firstReadWithNothingToMove_storeTheDefaultValues() throws {
        let storage = InMemoryAppLockDeviceSettingsStorage()
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage)

        _ = sut.delay

        #expect(storage.settings == AppLockDeviceSettings(erasesAfterFailedPasswords: false, delaySeconds: 0))
    }

    /// Something other than Vault that can write the App Group's defaults changes nothing once the settings are
    /// stored.
    @Test
    func deviceSettings_onceStored_ignoreWhatTheDefaultsSay() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let storage = InMemoryAppLockDeviceSettingsStorage(
            settings: AppLockDeviceSettings(erasesAfterFailedPasswords: true, delaySeconds: 0),
        )
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage, userDefaults: userDefaults)

        userDefaults.set(false, forKey: Self.erasesKey)
        userDefaults.set(AppLockDelay.fifteenMinutes.rawValue, forKey: Self.delayKey)

        #expect(try sut.loadErasesAfterFailedPasswords())
        #expect(sut.erasesAfterFailedPasswords)
        #expect(sut.delay == .immediately)
    }

    /// The AutoFill extension can read them for the first time at the same moment as the app: whichever stores them
    /// first, the other reads what it stored, rather than replacing it.
    @Test
    func deviceSettings_storedFirstByAnotherProcess_areReadAsTheyStoredThem() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        userDefaults.set(AppLockDelay.oneMinute.rawValue, forKey: Self.delayKey)
        let theirs = AppLockDeviceSettings(erasesAfterFailedPasswords: true, delaySeconds: 300)
        let storage = InMemoryAppLockDeviceSettingsStorage()
        storage.storeFirstFromAnotherProcess(theirs)
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage, userDefaults: userDefaults)

        #expect(sut.delay == .fiveMinutes)
        #expect(try sut.loadErasesAfterFailedPasswords())
        #expect(storage.settings == theirs)
    }

    @Test
    func setErasesAfterFailedPasswords_withDeviceSettings_storesItThereAndNotInTheDefaults() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let storage = InMemoryAppLockDeviceSettingsStorage()
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage, userDefaults: userDefaults)

        try sut.setErasesAfterFailedPasswords(true)

        #expect(storage.settings?.erasesAfterFailedPasswords == true)
        #expect(userDefaults.object(forKey: Self.erasesKey) == nil)
        #expect(try AppLockSettingsStore.keepingDeviceSettings(in: storage).loadErasesAfterFailedPasswords())

        try sut.setErasesAfterFailedPasswords(false)

        #expect(storage.settings?.erasesAfterFailedPasswords == false)
    }

    @Test(arguments: AppLockDelay.allCases)
    func setDelay_withDeviceSettings_storesItThereAndNotInTheDefaults(delay: AppLockDelay) throws {
        let userDefaults = try UserDefaults.nonPersistent()
        let storage = InMemoryAppLockDeviceSettingsStorage()
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage, userDefaults: userDefaults)
        try sut.setErasesAfterFailedPasswords(true)

        try sut.setDelay(delay)

        #expect(storage.settings == AppLockDeviceSettings(
            erasesAfterFailedPasswords: true,
            delaySeconds: delay.rawValue,
        ))
        #expect(userDefaults.object(forKey: Self.delayKey) == nil)
        #expect(try AppLockSettingsStore.keepingDeviceSettings(in: storage).delay == delay)
    }

    @Test
    func deviceSettings_unknownDelay_isImmediately() throws {
        let storage = InMemoryAppLockDeviceSettingsStorage(
            settings: AppLockDeviceSettings(erasesAfterFailedPasswords: false, delaySeconds: 42),
        )

        #expect(try AppLockSettingsStore.keepingDeviceSettings(in: storage).delay == .immediately)
    }

    /// If they can't be read, each is its safer value, whatever the defaults say: the delay Immediately, and erasing
    /// shown as on. Anything that acts on erasing gets an error instead.
    @Test
    func deviceSettings_unreadable_failClosed() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        userDefaults.set(false, forKey: Self.erasesKey)
        userDefaults.set(AppLockDelay.fifteenMinutes.rawValue, forKey: Self.delayKey)
        let storage = InMemoryAppLockDeviceSettingsStorage(
            settings: AppLockDeviceSettings(erasesAfterFailedPasswords: false, delaySeconds: 900),
        )
        storage.failToLoad()
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage, userDefaults: userDefaults)

        #expect(sut.delay == .immediately)
        #expect(sut.erasesAfterFailedPasswords)
        #expect(throws: InMemoryAppLockDeviceSettingsStorage.Failure.self) {
            try sut.loadErasesAfterFailedPasswords()
        }
    }

    @Test
    func deviceSettings_cantBeStored_setThrowsAndLeavesThemAsTheyWere() throws {
        let stored = AppLockDeviceSettings(erasesAfterFailedPasswords: true, delaySeconds: 0)
        let storage = InMemoryAppLockDeviceSettingsStorage(settings: stored)
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage)
        storage.failToStore()

        #expect(throws: InMemoryAppLockDeviceSettingsStorage.Failure.self) {
            try sut.setErasesAfterFailedPasswords(false)
        }
        #expect(throws: InMemoryAppLockDeviceSettingsStorage.Failure.self) {
            try sut.setDelay(.fifteenMinutes)
        }

        #expect(storage.settings == stored)
        #expect(try sut.loadErasesAfterFailedPasswords())
        #expect(sut.delay == .immediately)
    }

    /// If what the defaults held can't be stored yet, it fails closed, and the defaults keep it to move next time.
    @Test
    func deviceSettings_moveCantBeStored_failsClosedAndMovesThemNextTime() throws {
        let userDefaults = try UserDefaults.nonPersistent()
        userDefaults.set(AppLockDelay.fiveMinutes.rawValue, forKey: Self.delayKey)
        let storage = InMemoryAppLockDeviceSettingsStorage()
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage, userDefaults: userDefaults)
        storage.failToStore()

        #expect(sut.delay == .immediately)
        #expect(throws: InMemoryAppLockDeviceSettingsStorage.Failure.self) {
            try sut.loadErasesAfterFailedPasswords()
        }
        #expect(storage.settings == nil)
        #expect(userDefaults.integer(forKey: Self.delayKey) == AppLockDelay.fiveMinutes.rawValue)

        storage.failToStore(false)

        #expect(sut.delay == .fiveMinutes)
        #expect(userDefaults.object(forKey: Self.delayKey) == nil)
    }

    // MARK: - Keep Out of Time Machine

    @Test
    func includesVaultInBackups_isOffByDefault() throws {
        #expect(try !AppLockSettingsStore.keepingDeviceSettings().loadIncludesVaultInBackups())
        #expect(try !AppLockSettingsStore(userDefaults: .nonPersistent()).loadIncludesVaultInBackups())
    }

    /// It's kept with erasing and the delay, where only Vault can change it, and leaves them as they were.
    @Test
    func setIncludesVaultInBackups_storesItWithTheOtherDeviceSettings() throws {
        let storage = InMemoryAppLockDeviceSettingsStorage(
            settings: AppLockDeviceSettings(erasesAfterFailedPasswords: true, delaySeconds: 60),
        )
        let sut = try AppLockSettingsStore.keepingDeviceSettings(in: storage)

        try sut.setIncludesVaultInBackups(true)

        #expect(storage.settings == AppLockDeviceSettings(
            erasesAfterFailedPasswords: true,
            delaySeconds: 60,
            includesVaultInBackups: true,
        ))
        #expect(try AppLockSettingsStore.keepingDeviceSettings(in: storage).loadIncludesVaultInBackups())
    }

    /// Only the Mac has the setting, so there's nowhere else to keep it.
    @Test
    func setIncludesVaultInBackups_withoutDeviceSettings_throws() throws {
        let sut = try AppLockSettingsStore(userDefaults: .nonPersistent())

        #expect(throws: CocoaError.self) {
            try sut.setIncludesVaultInBackups(true)
        }
    }

    private static let delayKey = "vault.preferences.app-lock.delay"
    private static let erasesKey = "vault.preferences.app-lock.erases-after-failed-passwords"
}
