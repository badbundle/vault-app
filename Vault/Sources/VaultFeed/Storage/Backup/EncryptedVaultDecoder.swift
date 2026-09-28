import CryptoEngine
import Foundation
import FoundationExtensions
import VaultBackup
import VaultCore

/// @mockable(typealias: Key = KeyData<32>)
public protocol EncryptedVaultDecoder<Key>: Sendable {
    associatedtype Key: Sendable

    func decryptAndDecode(
        key: Key,
        encryptedVault: EncryptedVault,
    ) throws -> VaultApplicationPayload
    /// Throws if the given `key` cannot decrypt this vault.
    func verifyCanDecrypt(key: Key, encryptedVault: EncryptedVault) throws
}

/// From an encrypted vault, deconstruct to application-level items.
public final class EncryptedVaultDecoderImpl: EncryptedVaultDecoder, Sendable {
    public init() {}

    public func verifyCanDecrypt(key: KeyData<32>, encryptedVault: EncryptedVault) throws {
        try rethrowing {
            try VaultBackupDecryptor(key: key).verifyCanDecrypt(encryptedVault: encryptedVault)
        }
    }

    public func decryptAndDecode(
        key: KeyData<32>,
        encryptedVault: EncryptedVault,
    ) throws -> VaultApplicationPayload {
        try rethrowing {
            let backupDecoder = VaultBackupDecryptor(key: key)
            let payload = try backupDecoder.decryptBackupPayload(from: encryptedVault)
            let itemDecoder = VaultBackupItemDecoder()
            let tagDecoder = VaultBackupTagDecoder()
            return try .init(
                userDescription: payload.userDescription,
                items: payload.items.map {
                    try itemDecoder.decode(backupItem: $0)
                },
                tags: payload.tags.map {
                    try tagDecoder.decode(tag: $0)
                },
                killphraseKeys: Self.keys(payload.killphraseKeys),
                searchPassphraseKeys: Self.keys(payload.searchPassphraseKeys),
            )
        }
    }

    /// A backup's HMAC keys: none from a backup made before they were included, and any that isn't a whole key is
    /// left out.
    private static func keys(_ keys: [Data]?) -> [KeyData<32>] {
        (keys ?? []).compactMap { try? KeyData<32>(data: $0) }
    }

    private func rethrowing<T>(from body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let decodingError as VaultBackupDecryptor.Error {
            switch decodingError {
            case .incompatibleVersion:
                throw EncryptedVaultDecoderError.incompatibleVersion
            case .decryptionFailed:
                throw EncryptedVaultDecoderError.decryption
            case .decodingFailed:
                throw EncryptedVaultDecoderError.decoding
            }
        }
    }
}

// MARK: - Error

enum EncryptedVaultDecoderError: Equatable, Hashable, Error, LocalizedError {
    case incompatibleVersion
    case decryption
    case decoding

    var errorDescription: String? {
        switch self {
        case .incompatibleVersion: "Incompatible Export Version"
        case .decoding: "Decoding Failed"
        case .decryption: "Decryption Failed"
        }
    }

    var failureReason: String? {
        switch self {
        case .incompatibleVersion:
            """
            This backup was exported with a different version of the Vault app which is \
            incompatible with this version. You might need to install an older version of the app.
            """
        case .decoding:
            """
            The data within this backup was able to be decrypted, but it is malformed. \
            This might have been due to an export error or other data tampering. \
            You will need to foresically analyse the export to resolve this.
            """
        case .decryption:
            """
            Unable to decrypt this Vault. Please check that the decryption password is correct.
            """
        }
    }
}
