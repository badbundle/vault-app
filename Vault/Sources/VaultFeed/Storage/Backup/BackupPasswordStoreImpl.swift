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
public final class BackupPasswordStoreImpl: BackupPasswordStore {
    private let secureStorage: any SecureStorage
    private let clock: any EpochClock

    public init(secureStorage: any SecureStorage, clock: any EpochClock) {
        self.secureStorage = secureStorage
        self.clock = clock
    }

    public func fetchPassword() async throws -> DerivedEncryptionKey? {
        guard let encodedPassword = try await secureStorage.retrieve(key: KeychainKey.backupPassword) else {
            // Keep the record in step: whatever it says, no password is set.
            try? await secureStorage.remove(key: KeychainKey.backupPasswordMetadata)
            return nil
        }
        let decoded = try backupPasswordDecoder().decode(BackupPasswordContainer.self, from: encodedPassword)
        await recordMetadataIfMissing()
        return decoded.password
    }

    public func set(password: DerivedEncryptionKey) async throws {
        let container = BackupPasswordContainer(password: password)
        let encodedPassword = try backupPasswordEncoder().encode(container)
        try await secureStorage.store(data: encodedPassword, forKey: KeychainKey.backupPassword)
        // The password is stored now, so failing to record that mustn't fail the whole change:
        // without a record, the status falls back to the password's own attributes.
        try? await storeMetadata(BackupPasswordMetadata(lastSetDate: clock.currentDate))
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
        static let backupPassword = VaultIdentifiers.SecureStorageKey.backupPassword
        static let backupPasswordMetadata = VaultIdentifiers.SecureStorageKey.backupPasswordMetadata
    }
}
