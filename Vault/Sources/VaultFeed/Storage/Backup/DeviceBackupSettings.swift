import Foundation
import FoundationExtensions
import VaultCore

/// The plain store's backup settings, which turning encryption on moves into the real vault's own
/// (`VaultEncryptionConverter`).
public protocol DeviceBackupSettingsMoving: Sendable {
    /// The backup password, and when it was set, or `nil` if none is set. Asks the user to authenticate, if one is.
    func readBackupPassword() async throws -> StoredBackupPassword?
    /// The settings as they are now, with `backupPassword` as the password. Never asks the user anything.
    func read(backupPassword: StoredBackupPassword?) async -> VaultBackupSettings
    /// Deletes them, so none are left outside the encrypted vault. Does nothing for settings that aren't there.
    func delete() async throws
}

/// The plain store's backup settings, device-wide, where they've always been: the backup password and its record in
/// the keychain, and the last backup event, the auto-backup configuration and the PDF backup's hint in
/// `UserDefaults`.
///
/// Once encryption is on, each vault keeps its own in its payload instead (`OpenVaultBackupSettings`), and these are
/// moved into the real vault, then deleted. An erase deletes them too (`VaultEraser`).
@MainActor
public final class DeviceBackupSettings: DeviceBackupSettingsMoving {
    /// The keychain's backup password (`BackupPasswordStoreImpl`), on `secureStorage`.
    let passwordStore: any BackupPasswordStore
    private let secureStorage: any SecureStorage
    private let defaults: Defaults

    /// - Parameters:
    ///   - passwordStore: The keychain's backup password (`BackupPasswordStoreImpl`), on `secureStorage`.
    ///   - defaults: The `UserDefaults` the rest are in.
    public init(passwordStore: any BackupPasswordStore, secureStorage: any SecureStorage, defaults: Defaults) {
        self.passwordStore = passwordStore
        self.secureStorage = secureStorage
        self.defaults = defaults
    }

    public func readBackupPassword() async throws -> StoredBackupPassword? {
        guard let password = try await passwordStore.fetchPassword() else { return nil }
        // Only when it was set: the record says nothing more.
        let lastSetDate = try? await passwordStore.fetchPasswordMetadata()?.lastSetDate
        return StoredBackupPassword(password: password, lastSetDate: lastSetDate)
    }

    public func read(backupPassword: StoredBackupPassword?) -> VaultBackupSettings {
        VaultBackupSettings(
            backupPassword: backupPassword,
            lastBackupEvent: defaults.get(for: Defaults.lastBackupEventKey),
            autoBackup: defaults.get(for: Defaults.autoBackupConfigurationKey) ?? AutoBackupConfiguration(),
            pdfUserHint: defaults.get(for: Defaults.pdfUserHintKey),
        )
    }

    /// Saves every setting in `settings` but the backup password, which the keychain keeps (`passwordStore`).
    func save(_ settings: VaultBackupSettings) throws {
        if let event = settings.lastBackupEvent {
            try defaults.set(event, for: Defaults.lastBackupEventKey)
        } else {
            defaults.clear(Defaults.lastBackupEventKey)
        }
        try defaults.set(settings.autoBackup, for: Defaults.autoBackupConfigurationKey)
        if let hint = settings.pdfUserHint {
            try defaults.set(hint, for: Defaults.pdfUserHintKey)
        } else {
            defaults.clear(Defaults.pdfUserHintKey)
        }
    }

    /// Deletes `UserDefaults` first, which can't fail, so the keychain failing leaves nothing else behind.
    public func delete() async throws {
        defaults.clear(Defaults.lastBackupEventKey)
        defaults.clear(Defaults.autoBackupConfigurationKey)
        defaults.clear(Defaults.pdfUserHintKey)
        try await secureStorage.remove(key: VaultIdentifiers.SecureStorageKey.backupPassword.keychainService)
        try await secureStorage.remove(key: VaultIdentifiers.SecureStorageKey.backupPasswordMetadata.keychainService)
    }
}
