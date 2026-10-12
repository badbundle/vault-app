import Foundation
import FoundationExtensions
import VaultCore

/// Loads (or generates and stores) the 256-bit HMAC keys used by
/// `SearchPassphraseDigester`: the vault's own key, and the keys restored
/// backups brought with them (see `VaultPhraseKeyrings`).
///
/// The app reads the open vault's (`OpenVaultPhraseKeyrings`), kept where
/// the killphrase keys are: an encrypted vault's in its payload, and the
/// plain store's in the device keychain with `.whenUnlocked` access (no
/// biometric prompt) (`SearchPassphraseKeyStoreImpl`).
///
/// `loadOrCreate` is idempotent: on first call after install/upgrade, it
/// generates a random key and stores it; on every subsequent call it
/// returns the stored value.
///
/// @mockable(typealias: Key = KeyData<32>)
public protocol SearchPassphraseKeyStore<Key>: Sendable {
    associatedtype Key: Sendable
    /// The vault's own key, which every new digest is made with.
    func loadOrCreate() async throws -> Key
    /// The keys restored backups brought, which their search passphrases were digested with elsewhere, or before an
    /// erase. Never the vault's own key.
    func loadKeysFromBackups() async throws -> [Key]
    /// Adds the keys a restored backup brought, skipping any already on the keyring.
    func addKeysFromBackup(_ keys: [Key]) async throws
}

extension SearchPassphraseKeyStore {
    /// Every key on the keyring: the vault's own first, then those from backups. A backup carries them all.
    public func loadKeyring() async throws -> [Key] {
        try await [loadOrCreate()] + loadKeysFromBackups()
    }
}

/// The search passphrase keyring in this device's keychain (`HMACKeyring`): the plain store's.
public struct SearchPassphraseKeyStoreImpl: SearchPassphraseKeyStore {
    private let keyring: HMACKeyring

    public init(secureStorage: any SecureStorage) {
        keyring = HMACKeyring(
            secureStorage: secureStorage,
            ownKeyItem: .searchPassphraseKey,
            backupKeysItem: .searchPassphraseBackupKeys,
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
