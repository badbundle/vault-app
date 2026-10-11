import Foundation
import SwiftSecurity

/// The app lock's settings, kept in the defaults the app shares with its extensions.
///
/// The AutoFill and widget extensions read them too: while the lock is on, neither shows a code until the user has
/// authenticated. Only the app changes them, through `AppLockService`.
///
/// On the Mac, erasing after failed passwords and the Require Unlock delay are kept in the keychain instead
/// (`AppLockDeviceSettingsKeychainStorage`), where only Vault can change them: other processes running as the user can
/// be allowed into the App Group's container there, and so its defaults. On iOS, only Vault can reach that container,
/// so they stay in its defaults (VAULT-118). The first time the Mac reads them, what an earlier version kept in the
/// defaults moves to the keychain, once. If the keychain can't be read, each reads as its safer value.
///
/// `UserDefaults` is documented thread-safe, and this only reads and writes single values through it. Marked
/// `@unchecked Sendable` so the widget extension's actor can hold it.
public struct AppLockSettingsStore: @unchecked Sendable { // swiftlint:disable:this no_unchecked_sendable
    private let userDefaults: UserDefaults
    /// Where erasing after failed passwords and the delay are kept, or `nil` to keep them in `userDefaults`.
    private let deviceSettings: (any AppLockDeviceSettingsStorage)?

    public init(userDefaults: UserDefaults) {
        self.init(userDefaults: userDefaults, deviceSettings: nil)
    }

    init(userDefaults: UserDefaults, deviceSettings: (any AppLockDeviceSettingsStorage)?) {
        self.userDefaults = userDefaults
        self.deviceSettings = deviceSettings
    }

    /// The App Group's defaults, which the app and every extension read, and on the Mac, the keychain item they share.
    public static func shared() -> AppLockSettingsStore {
        #if os(macOS)
        AppLockSettingsStore(
            userDefaults: VaultSharedStorage.userDefaults(),
            deviceSettings: AppLockDeviceSettingsKeychainStorage(),
        )
        #else
        AppLockSettingsStore(userDefaults: VaultSharedStorage.userDefaults())
        #endif
    }

    /// Whether the app asks for device authentication before it shows the vault. Off until the user turns it on.
    public var isEnabled: Bool {
        get {
            userDefaults.bool(forKey: VaultIdentifiers.Preferences.AppLock.isEnabled)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: VaultIdentifiers.Preferences.AppLock.isEnabled)
        }
    }

    /// Whether `AppLockPasswordAttemptCounter.eraseThreshold` wrong App Lock Passwords in a row erase every vault on
    /// this device (VAULT-34), for showing in Settings. Off unless the user turns it on, and on if it can't be read.
    /// Anything that acts on it reads it with `loadErasesAfterFailedPasswords()`.
    ///
    /// It's a setting of the device, not of a vault, like the attempt count, so every vault shares it. On iOS, it's
    /// stored only while it's on, and deleted with the app, so a reinstall never finds it on for a new password; on
    /// the Mac, the App Group's container and the keychain outlast the app. A new password starts with it off, and an
    /// erase turns it off (`VaultEraser`).
    public var erasesAfterFailedPasswords: Bool {
        (try? loadErasesAfterFailedPasswords()) ?? true
    }

    /// Whether erasing after failed passwords is on.
    ///
    /// - Throws: If it can't be read, so that nothing is done on a guess at it: neither erasing when the user never
    ///   turned it on, nor going on when they did. It's only ever thrown on the Mac.
    public func loadErasesAfterFailedPasswords() throws -> Bool {
        guard let deviceSettings else {
            return userDefaults.bool(forKey: VaultIdentifiers.Preferences.AppLock.erasesAfterFailedPasswords)
        }
        return try loadDeviceSettings(from: deviceSettings).erasesAfterFailedPasswords
    }

    /// Turns erasing after failed passwords on or off. It's in storage by the time this returns.
    ///
    /// - Throws: If it couldn't be stored, and it's as it was. It's only ever thrown on the Mac.
    public func setErasesAfterFailedPasswords(_ erases: Bool) throws {
        guard let deviceSettings else {
            if erases {
                userDefaults.set(true, forKey: VaultIdentifiers.Preferences.AppLock.erasesAfterFailedPasswords)
            } else {
                userDefaults.removeObject(forKey: VaultIdentifiers.Preferences.AppLock.erasesAfterFailedPasswords)
            }
            return
        }
        var settings = try loadDeviceSettings(from: deviceSettings)
        settings.erasesAfterFailedPasswords = erases
        try deviceSettings.save(settings)
    }

    /// How long the app can be in the background before it locks. Immediately unless the user has chosen otherwise,
    /// and immediately for any value this version doesn't know, or if it can't be read.
    public var delay: AppLockDelay {
        guard let deviceSettings else {
            return AppLockDelay(rawValue: userDefaults.integer(forKey: VaultIdentifiers.Preferences.AppLock.delay))
                ?? .default
        }
        return (try? loadDeviceSettings(from: deviceSettings).delay) ?? .default
    }

    /// Changes how long the app can be in the background before it locks. It's in storage by the time this returns.
    ///
    /// - Throws: If it couldn't be stored, and it's as it was. It's only ever thrown on the Mac.
    public func setDelay(_ delay: AppLockDelay) throws {
        guard let deviceSettings else {
            userDefaults.set(delay.rawValue, forKey: VaultIdentifiers.Preferences.AppLock.delay)
            return
        }
        var settings = try loadDeviceSettings(from: deviceSettings)
        settings.delaySeconds = delay.rawValue
        try deviceSettings.save(settings)
    }

    /// The settings in `storage`. The first time there are none, so what the defaults hold, or the defaults' own
    /// values, are stored there, and taken out of the defaults: they're only ever read from the defaults once, and
    /// never again once they're stored, whatever the defaults say later. If another process, such as the AutoFill
    /// extension, stores them first, its are read instead.
    private func loadDeviceSettings(from storage: any AppLockDeviceSettingsStorage) throws -> AppLockDeviceSettings {
        if let settings = try storage.load() {
            return settings
        }
        let moved = AppLockDeviceSettings(
            erasesAfterFailedPasswords: userDefaults.bool(
                forKey: VaultIdentifiers.Preferences.AppLock.erasesAfterFailedPasswords,
            ),
            delaySeconds: userDefaults.integer(forKey: VaultIdentifiers.Preferences.AppLock.delay),
        )
        guard try storage.add(moved) else {
            guard let settings = try storage.load() else { throw SwiftSecurityError(rawValue: errSecItemNotFound) }
            return settings
        }
        userDefaults.removeObject(forKey: VaultIdentifiers.Preferences.AppLock.erasesAfterFailedPasswords)
        userDefaults.removeObject(forKey: VaultIdentifiers.Preferences.AppLock.delay)
        return moved
    }
}
