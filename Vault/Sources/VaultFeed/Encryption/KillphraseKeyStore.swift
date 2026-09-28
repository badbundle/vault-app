import Foundation
import FoundationExtensions
import VaultCore

/// Loads (or generates and stores) the 256-bit HMAC keys used by
/// `KillphraseDigester`: this device's own key, and the keys restored
/// backups brought with them (see `HMACKeyring`).
///
/// The keys are held in the device keychain with `.whenUnlocked` access (no
/// biometric prompt) so the silent-delete-on-search UX continues to work
/// the moment the device is unlocked, without depending on whether the
/// user has opened the backup-password flow.
///
/// `loadOrCreate` is idempotent: on first call after install/upgrade, it
/// generates a random key and stores it; on every subsequent call it
/// returns the stored value.
///
/// @mockable(typealias: Key = KeyData<32>)
public protocol KillphraseKeyStore<Key>: Sendable {
    associatedtype Key: Sendable
    /// This device's own key, which every new digest is made with.
    func loadOrCreate() async throws -> Key
    /// The keys restored backups brought, which their killphrases were digested with elsewhere, or before an erase.
    /// Never this device's own key.
    func loadKeysFromBackups() async throws -> [Key]
    /// Adds the keys a restored backup brought, skipping any already on the keyring.
    func addKeysFromBackup(_ keys: [Key]) async throws
}

extension KillphraseKeyStore {
    /// Every key on the keyring: this device's own first, then those from backups. A backup carries them all.
    public func loadKeyring() async throws -> [Key] {
        try await [loadOrCreate()] + loadKeysFromBackups()
    }
}

public struct KillphraseKeyStoreImpl: KillphraseKeyStore {
    private let keyring: HMACKeyring

    public init(secureStorage: any SecureStorage) {
        keyring = HMACKeyring(
            secureStorage: secureStorage,
            ownKeyItem: .killphraseKey,
            backupKeysItem: .killphraseBackupKeys,
        )
    }

    public func loadOrCreate() async throws -> KeyData<32> {
        try await keyring.loadOrCreateOwnKey()
    }

    public func loadKeysFromBackups() async throws -> [KeyData<32>] {
        try await keyring.loadKeysFromBackups()
    }

    public func addKeysFromBackup(_ keys: [KeyData<32>]) async throws {
        try await keyring.addKeysFromBackup(keys)
    }
}
