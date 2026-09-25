import Foundation
import FoundationExtensions
import VaultKeygen

public final class BackupPasswordStoreImpl: BackupPasswordStore {
    private let secureStorage: any SecureStorage

    public init(secureStorage: any SecureStorage) {
        self.secureStorage = secureStorage
    }

    public func fetchPassword() async throws -> DerivedEncryptionKey? {
        struct NotFoundInKeychain: Error {}

        func fetchDataFromKeychainIfPresent(key: String) async throws -> Data {
            if let item = try await secureStorage.retrieve(key: key) {
                item
            } else {
                throw NotFoundInKeychain()
            }
        }

        do {
            let encodedPassword = try await fetchDataFromKeychainIfPresent(key: KeychainKey.backupPassword)
            let decoded = try backupPasswordDecoder().decode(BackupPasswordContainer.self, from: encodedPassword)
            return decoded.password
        } catch is NotFoundInKeychain {
            return nil
        }
    }

    public func set(password: DerivedEncryptionKey) async throws {
        let container = BackupPasswordContainer(password: password)
        let encodedPassword = try backupPasswordEncoder().encode(container)
        try await secureStorage.store(data: encodedPassword, forKey: KeychainKey.backupPassword)
    }

    public func fetchPasswordMetadata() async throws -> BackupPasswordMetadata? {
        guard let attributes = try await secureStorage.attributes(key: KeychainKey.backupPassword) else {
            return nil
        }
        // `set(password:)` replaces the item rather than updating it, so its
        // modification date is when the current password was set.
        return BackupPasswordMetadata(lastSetDate: attributes.modificationDate)
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
    }
}
