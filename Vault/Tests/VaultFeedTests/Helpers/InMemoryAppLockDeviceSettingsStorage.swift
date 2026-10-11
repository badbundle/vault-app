import Foundation
import FoundationExtensions
@testable import VaultFeed

/// Keeps the app lock's device settings in memory, as the Mac's keychain item does, and fails when the test says.
final class InMemoryAppLockDeviceSettingsStorage: AppLockDeviceSettingsStorage {
    struct Failure: Error {}

    private struct State {
        var settings: AppLockDeviceSettings?
        var failsToLoad = false
        var failsToStore = false
        /// Settings another process stores just before this one adds its own.
        var storedFirstByAnotherProcess: AppLockDeviceSettings?
    }

    private let state: SharedMutex<State>

    init(settings: AppLockDeviceSettings? = nil) {
        state = SharedMutex(State(settings: settings))
    }

    /// The settings as they're stored now.
    var settings: AppLockDeviceSettings? {
        state.get { $0.settings }
    }

    /// Makes every read fail, as a keychain that can't be read does, or read again.
    func failToLoad(_ fails: Bool = true) {
        state.modify { $0.failsToLoad = fails }
    }

    /// Makes every add and save fail, or succeed again.
    func failToStore(_ fails: Bool = true) {
        state.modify { $0.failsToStore = fails }
    }

    /// Has another process, such as the AutoFill extension, store `settings` just before the next add.
    func storeFirstFromAnotherProcess(_ settings: AppLockDeviceSettings) {
        state.modify { $0.storedFirstByAnotherProcess = settings }
    }

    func load() throws -> AppLockDeviceSettings? {
        try state.get { state in
            guard !state.failsToLoad else { throw Failure() }
            return state.settings
        }
    }

    func add(_ settings: AppLockDeviceSettings) throws -> Bool {
        try state.modify { state in
            guard !state.failsToStore else { throw Failure() }
            if let other = state.storedFirstByAnotherProcess {
                state.settings = other
                state.storedFirstByAnotherProcess = nil
            }
            guard state.settings == nil else { return false }
            state.settings = settings
            return true
        }
    }

    func save(_ settings: AppLockDeviceSettings) throws {
        try state.modify { state in
            guard !state.failsToStore else { throw Failure() }
            state.settings = settings
        }
    }
}

extension AppLockSettingsStore {
    /// Settings that keep erasing after failed passwords and the delay in `deviceSettings`, as the Mac does, and the
    /// rest in new defaults of their own.
    static func keepingDeviceSettings(
        in deviceSettings: InMemoryAppLockDeviceSettingsStorage = InMemoryAppLockDeviceSettingsStorage(),
        userDefaults: UserDefaults? = nil,
    ) throws -> AppLockSettingsStore {
        try AppLockSettingsStore(userDefaults: userDefaults ?? .nonPersistent(), deviceSettings: deviceSettings)
    }
}
