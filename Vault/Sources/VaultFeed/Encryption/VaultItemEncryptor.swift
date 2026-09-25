import CryptoEngine
import Foundation
import VaultCore
import VaultKeygen

/// Use for encoding and encrypting encrypted vault items, so they are ready for storage.
///
/// Counterpart to `VaultItemDecryptor`.
struct VaultItemEncryptor {
    private let key: DerivedEncryptionKey

    init(key: DerivedEncryptionKey) {
        self.key = key
    }

    /// Encrypts and encodes an encryptable item.
    func encrypt(item: some VaultItemEncryptable) throws -> EncryptedItem {
        let containerEncoding = try item.makeEncryptedContainer()
        let encodedFormat = try makeEncoder().encode(containerEncoding)
        let encryptor = AESGCMEncryptor(key: key.key.data)
        let iv = KeyData<32>.random()
        let encrypted = try encryptor.encrypt(plaintext: encodedFormat, iv: iv.data)
        return EncryptedItem(
            version: "1.0.0",
            // The plaintext title is always a copy of the encrypted one, so the two can't differ.
            title: containerEncoding.title,
            data: encrypted.ciphertext,
            authentication: encrypted.authenticationTag,
            encryptionIV: iv.data,
            keygenSalt: key.salt,
            keygenSignature: key.keyDervier.rawValue,
        )
    }

    /// The encoder for the intermediate format before it is encrypted.
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys] // predictable output
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        return encoder
    }
}
