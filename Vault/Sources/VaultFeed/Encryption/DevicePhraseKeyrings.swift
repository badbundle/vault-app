import Foundation
import FoundationExtensions
import VaultCore

/// The killphrase and search passphrase keyrings this device keeps in its keychain, for the vaults that don't keep
/// their own in their payload (`VaultPhraseKeyrings`):
///
/// - **This device's keyrings** (`HMACKeyring`), where they've always been: the plain store's, which turning encryption
///   on moves into the real vault. Before vaults kept their own, every vault used these. So while an encrypted vault
///   made then may not have opened since, they stay: each such vault takes a copy of them the first time it opens
///   (`OpenVaultPhraseKeyrings`), and only an erase deletes them.
/// - **The keyrings while the password is off** (`SecureStorageKey.phraseKeyringsWhilePasswordOff`): those of the
///   encrypted vault the device key opens. Turning the App Lock Password off moves the vault's keyrings here, and
///   turning it back on moves them back (`VaultPasswordChangeService`). A vault whose password was turned off before
///   vaults kept their own has none here, and uses this device's keyrings.
///
/// Every item is read without a biometric prompt, never synced, and an erase deletes them all (`VaultEraser`).
public struct DevicePhraseKeyrings: Sendable {
    private let secureStorage: any SecureStorage
    let killphrase: HMACKeyring
    let searchPassphrase: HMACKeyring

    public init(secureStorage: any SecureStorage) {
        self.secureStorage = secureStorage
        killphrase = HMACKeyring(
            secureStorage: secureStorage,
            ownKeyItem: .killphraseKey,
            backupKeysItem: .killphraseBackupKeys,
        )
        searchPassphrase = HMACKeyring(
            secureStorage: secureStorage,
            ownKeyItem: .searchPassphraseKey,
            backupKeysItem: .searchPassphraseBackupKeys,
        )
    }

    /// This device's keyring of `kind`.
    func keyring(_ kind: VaultPhraseKeyrings.Kind) -> HMACKeyring {
        switch kind {
        case .killphrase: killphrase
        case .searchPassphrase: searchPassphrase
        }
    }
}

// MARK: - This device's keyrings

extension DevicePhraseKeyrings {
    /// This device's keyrings, to move into the only vault there is, as turning encryption on does: each kind's own
    /// key, or a new one if it has none yet, and its keys from backups. Nothing is stored or deleted.
    public func loadForMoving() async throws -> VaultPhraseKeyrings {
        try await VaultPhraseKeyrings(
            killphrase: killphrase.loadForMoving(),
            searchPassphrase: searchPassphrase.loadForMoving(),
        )
    }

    /// Keyrings of its own for a vault that shares this device's keyrings with other vaults, which may not have opened
    /// since: a new key of its own for each kind, and every key of this device's to match against
    /// (`VaultPhraseKeyrings.takingCopies(killphrase:searchPassphrase:)`). Nothing is stored or deleted.
    func copiesForAVault() async throws -> VaultPhraseKeyrings {
        let killphraseKeys = try await killphrase.loadAllKeys()
        let searchPassphraseKeys = try await searchPassphrase.loadAllKeys()
        return .takingCopies(killphraseKeys: killphraseKeys, searchPassphraseKeys: searchPassphraseKeys)
    }

    /// Deletes this device's keyrings, once the only vault that could need them holds them.
    public func delete() async throws {
        try await killphrase.delete()
        try await searchPassphrase.delete()
    }
}

// MARK: - While the password is off

extension DevicePhraseKeyrings {
    private var passwordOffItem: String {
        VaultIdentifiers.SecureStorageKey.phraseKeyringsWhilePasswordOff.keychainService
    }

    /// The keyrings of the vault the device key opens, or `nil` if it has none here: it uses this device's keyrings.
    func passwordOffKeyrings() async throws -> VaultPhraseKeyrings? {
        guard let data = try await secureStorage.retrieveSilent(key: passwordOffItem) else { return nil }
        return try JSONDecoder().decode(VaultPhraseKeyrings.self, from: data)
    }

    /// Stores the keyrings of the vault the device key opens, replacing any there were.
    func storePasswordOffKeyrings(_ keyrings: VaultPhraseKeyrings) async throws {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        try await secureStorage.storeSilent(data: encoder.encode(keyrings), forKey: passwordOffItem)
    }

    /// Deletes the keyrings of the vault the device key opened, once that vault holds them again, or before a vault
    /// that has none of its own starts using this device's keyrings.
    func deletePasswordOffKeyrings() async throws {
        try await secureStorage.remove(key: passwordOffItem)
    }
}
