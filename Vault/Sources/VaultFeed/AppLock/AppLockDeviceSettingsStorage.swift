import Foundation
import Security
import SwiftSecurity

/// The settings that protect the vault and belong to the device, not to a vault: erasing after failed passwords, the
/// Require Unlock delay, and whether the vault is kept out of the device's own backups. Weakening the first two needs
/// the App Lock Password or the user's authentication, and the last is on unless the user turns it off (C7), so on the
/// Mac, `AppLockSettingsStore` keeps them where only Vault can change them.
struct AppLockDeviceSettings: Codable, Equatable, Sendable {
    /// Whether `AppLockPasswordAttemptCounter.eraseThreshold` wrong App Lock Passwords in a row erase every vault.
    var erasesAfterFailedPasswords: Bool
    /// The Require Unlock delay in seconds, as an `AppLockDelay` raw value. Kept as a number, so a value this version
    /// doesn't know reads as Immediately rather than failing to decode.
    var delaySeconds: Int
    /// Whether the user has turned Keep Out of Time Machine off, so the device's own backups include the vault
    /// (`VaultStorageBackupExclusion`). Off unless they do.
    var includesVaultInBackups: Bool

    var delay: AppLockDelay {
        AppLockDelay(rawValue: delaySeconds) ?? .default
    }

    init(erasesAfterFailedPasswords: Bool, delaySeconds: Int, includesVaultInBackups: Bool = false) {
        self.erasesAfterFailedPasswords = erasesAfterFailedPasswords
        self.delaySeconds = delaySeconds
        self.includesVaultInBackups = includesVaultInBackups
    }

    /// Settings stored before a setting was added read it as its default, which is always the protective one, rather
    /// than failing to decode, which would leave every setting unreadable and unchangeable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        erasesAfterFailedPasswords = try container.decode(Bool.self, forKey: .erasesAfterFailedPasswords)
        delaySeconds = try container.decode(Int.self, forKey: .delaySeconds)
        includesVaultInBackups = try container.decodeIfPresent(Bool.self, forKey: .includesVaultInBackups) ?? false
    }
}

/// Where `AppLockSettingsStore` keeps `AppLockDeviceSettings`, when not in the defaults.
protocol AppLockDeviceSettingsStorage: Sendable {
    /// The settings, or `nil` if none have been stored.
    func load() throws -> AppLockDeviceSettings?
    /// Stores the settings if none are stored yet. `false`, changing nothing, if some are.
    func add(_ settings: AppLockDeviceSettings) throws -> Bool
    /// Replaces the settings, or stores them if there are none. They're in storage by the time this returns.
    func save(_ settings: AppLockDeviceSettings) throws
}

/// Keeps `AppLockDeviceSettings` in the keychain, on this device only (VAULT-118).
///
/// On the Mac, a process running as the user can be allowed into Vault's App Group, and change its defaults. It can't
/// change Vault's keychain items: only apps of Vault's team that are given its access group can. So these settings are
/// kept here, beside the count of wrong passwords (`AppLockPasswordAttemptKeychainStorage`).
///
/// The item is readable once the device has been unlocked after starting up, as the defaults are, so a launch while
/// the screen is locked still reads the user's settings. It never syncs to iCloud Keychain, and never moves to another
/// device with a backup. It's in the keychain access group the app shares with the AutoFill extension only
/// (`SharedKeychainItem`), so the AutoFill extension reads the same settings.
struct AppLockDeviceSettingsKeychainStorage: AppLockDeviceSettingsStorage {
    let item: SharedKeychainItem

    init(item: SharedKeychainItem = SharedKeychainItem(key: .appLockDeviceSettings)) {
        self.item = item
    }

    func load() throws -> AppLockDeviceSettings? {
        guard let data = try item.data() else { return nil }
        return try JSONDecoder().decode(AppLockDeviceSettings.self, from: data)
    }

    func add(_ settings: AppLockDeviceSettings) throws -> Bool {
        try item.add(Self.attributes(for: settings))
    }

    /// Updates the item in place, so there's never a moment without it.
    func save(_ settings: AppLockDeviceSettings) throws {
        try item.save(Self.attributes(for: settings))
    }

    /// Moves the settings out of the App Group's keychain access group, where versions before VAULT-129 kept them
    /// (`SharedKeychainItem.moveFromTheAppGroup()`).
    func moveFromTheAppGroup() throws {
        try item.moveFromTheAppGroup()
    }

    /// What's stored in the item: the settings, readable once the device has been unlocked after starting up, on this
    /// device only.
    static func attributes(for settings: AppLockDeviceSettings) throws -> [String: Any] {
        try [
            kSecValueData as String: JSONEncoder().encode(settings),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}
