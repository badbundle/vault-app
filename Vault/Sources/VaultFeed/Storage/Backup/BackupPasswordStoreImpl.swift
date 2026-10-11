import Foundation
import FoundationExtensions
import VaultKeygen

/// Keeps the backup password in `SecureStorage`, where loading it needs user presence.
///
/// Next to it, the store keeps a non-secret record that a password is set, and when, which can be
/// read without authenticating. `fetchPasswordMetadata()` reads that record rather than the
/// password's own item, because reading even the attributes of an item that needs user presence
/// can fail without authentication. The record is written whenever a password is set, filled in
/// for older passwords the next time the password is loaded, and removed if loading finds no
/// password.
///
/// `SecureStorage` replaces an item by removing it and adding the new one, and the add can fail, as it does while the
/// device is locked. So an upgraded key (`upgradePassword(from:to:)`) is kept in an item of its own first, and only
/// then replaces the password's. If replacing it stops part way, leaving no password, the next load finds the upgraded
/// key and puts it back. Removing or setting a password removes that copy first, so it can never come back in place of
/// a password that's been removed or set since.
public final class BackupPasswordStoreImpl: BackupPasswordStore {
    private let secureStorage: any SecureStorage
    private let clock: any EpochClock

    public init(secureStorage: any SecureStorage, clock: any EpochClock) {
        self.secureStorage = secureStorage
        self.clock = clock
    }

    public func fetchPassword() async throws -> DerivedEncryptionKey? {
        var stored = try await secureStorage.retrieve(key: KeychainKey.backupPassword)
        if stored == nil {
            stored = try await restoreUpgradedPassword()
        }
        guard let encodedPassword = stored else {
            // Keep the record in step: whatever it says, no password is set.
            try? await secureStorage.remove(key: KeychainKey.backupPasswordMetadata)
            return nil
        }
        let decoded = try backupPasswordDecoder().decode(BackupPasswordContainer.self, from: encodedPassword)
        await recordMetadataIfMissing()
        return decoded.password
    }

    /// The copy of an upgraded key left from an upgrade that stopped part way goes first, so it can't come back in
    /// place of this password.
    public func set(password: DerivedEncryptionKey) async throws {
        let container = BackupPasswordContainer(password: password)
        let encodedPassword = try backupPasswordEncoder().encode(container)
        try await secureStorage.remove(key: KeychainKey.backupPasswordUpgrade)
        try await secureStorage.store(data: encodedPassword, forKey: KeychainKey.backupPassword)
        // The password is stored now, so failing to record that mustn't fail the whole change:
        // without a record, the status falls back to the password's own attributes.
        try? await storeMetadata(BackupPasswordMetadata(lastSetDate: clock.currentDate))
    }

    /// Keeps `new` in an item of its own, then puts it in the password's place. `old` isn't read, which would ask the
    /// user to authenticate: the store's caller makes sure no other password has been set since it loaded `old`
    /// (`OpenVaultBackupSettings`). The record of when the password was set stays as it is.
    public func upgradePassword(from _: DerivedEncryptionKey, to new: DerivedEncryptionKey) async throws {
        let encodedPassword = try backupPasswordEncoder().encode(BackupPasswordContainer(password: new))
        // If this fails, nothing has changed.
        try await secureStorage.store(data: encodedPassword, forKey: KeychainKey.backupPasswordUpgrade)
        // If this fails part way, with the password removed and not yet replaced, the next load restores `new`.
        try await secureStorage.store(data: encodedPassword, forKey: KeychainKey.backupPassword)
        // Left behind, it's a copy of the password, removed with it or when another is set.
        try? await secureStorage.remove(key: KeychainKey.backupPasswordUpgrade)
    }

    /// The upgraded key's copy goes first, so it can't come back as the password. Then the password, which is what
    /// decrypts backups. If the record can't be removed after it, it's removed the next time the password is loaded
    /// and isn't found.
    public func removePassword() async throws {
        try await secureStorage.remove(key: KeychainKey.backupPasswordUpgrade)
        try await secureStorage.remove(key: KeychainKey.backupPassword)
        try await secureStorage.remove(key: KeychainKey.backupPasswordMetadata)
    }

    public func fetchPasswordMetadata() async throws -> BackupPasswordMetadata? {
        if let record = try await secureStorage.retrieveSilent(key: KeychainKey.backupPasswordMetadata) {
            return decodeMetadata(record)
        }
        // No record: either there's no password, or it was set before the store kept one. The
        // password's attributes can tell which, where they're readable without authentication.
        guard let attributes = try await secureStorage.attributes(key: KeychainKey.backupPassword) else {
            return nil
        }
        // `set(password:)` replaces the item rather than updating it, so its
        // modification date is when the current password was set.
        return BackupPasswordMetadata(lastSetDate: attributes.modificationDate)
    }
}

// MARK: - Upgrade

extension BackupPasswordStoreImpl {
    /// For when there's no password: the upgraded key an upgrade that stopped part way left in its own item, put back
    /// as the password, or `nil` if there's none. Putting it back is best-effort: until it's done, it's found here.
    private func restoreUpgradedPassword() async throws -> Data? {
        guard let upgraded = try await secureStorage.retrieve(key: KeychainKey.backupPasswordUpgrade) else {
            return nil
        }
        do {
            try await secureStorage.store(data: upgraded, forKey: KeychainKey.backupPassword)
            try? await secureStorage.remove(key: KeychainKey.backupPasswordUpgrade)
        } catch {
            // Tried again the next time the password is loaded.
        }
        return upgraded
    }
}

// MARK: - Metadata

extension BackupPasswordStoreImpl {
    /// Records that a password is set if nothing has yet, for passwords set before the store kept
    /// a record. Only called once the password has been loaded, so it's known to exist.
    ///
    /// Best-effort: if this fails, it's tried again the next time the password is loaded.
    private func recordMetadataIfMissing() async {
        do {
            guard try await secureStorage.retrieveSilent(key: KeychainKey.backupPasswordMetadata) == nil else {
                return
            }
            // The password's modification date is when it was set, if it can be read.
            let attributes = try? await secureStorage.attributes(key: KeychainKey.backupPassword)
            try await storeMetadata(BackupPasswordMetadata(lastSetDate: attributes?.modificationDate))
        } catch {
            // Leave it for next time.
        }
    }

    private func storeMetadata(_ metadata: BackupPasswordMetadata) async throws {
        let record = try backupPasswordEncoder().encode(MetadataContainer(lastSetDate: metadata.lastSetDate))
        try await secureStorage.storeSilent(data: record, forKey: KeychainKey.backupPasswordMetadata)
    }

    /// The record existing is what says a password is set, so one that can't be decoded still
    /// counts, just without a date.
    private func decodeMetadata(_ record: Data) -> BackupPasswordMetadata {
        let container = try? backupPasswordDecoder().decode(MetadataContainer.self, from: record)
        return BackupPasswordMetadata(lastSetDate: container?.lastSetDate)
    }
}

// MARK: - Encoding

extension BackupPasswordStoreImpl {
    /// Codable container that is stored in the keychain.
    private struct BackupPasswordContainer: Codable {
        var key: KeyData<32>
        var salt: Data
        var keyDervier: VaultKeyDeriver.Signature

        init(password: DerivedEncryptionKey) {
            key = password.key
            salt = password.salt
            keyDervier = password.keyDervier
        }

        var password: DerivedEncryptionKey {
            DerivedEncryptionKey(key: key, salt: salt, keyDervier: keyDervier)
        }
    }

    /// Codable container for the record that a password is set. Nothing in it is secret.
    private struct MetadataContainer: Codable {
        var lastSetDate: Date?
    }

    private func backupPasswordEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private func backupPasswordDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private enum KeychainKey {
        static let backupPassword = VaultIdentifiers.SecureStorageKey.backupPassword.keychainService
        static let backupPasswordMetadata = VaultIdentifiers.SecureStorageKey.backupPasswordMetadata.keychainService
        static let backupPasswordUpgrade = VaultIdentifiers.SecureStorageKey.backupPasswordUpgrade.keychainService
    }
}
