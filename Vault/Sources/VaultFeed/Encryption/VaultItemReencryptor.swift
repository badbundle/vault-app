import CryptoEngine
import Foundation
import VaultCore
import VaultKeygen

/// Encrypts an encrypted item again under another key, as when it moves to a stronger key derivation (VAULT-128).
///
/// What's encrypted is decrypted and encrypted again byte for byte, never decoded, so the item holds exactly what it
/// held, whatever version of Vault encrypted it. Only the key, its salt and derivation, the IV and the ciphertext
/// change. The plaintext title and the item's version stay.
struct VaultItemReencryptor {
    /// - Throws: If `oldKey` doesn't decrypt the item.
    func reencrypt(
        _ item: EncryptedItem,
        from oldKey: DerivedEncryptionKey,
        to newKey: DerivedEncryptionKey,
    ) throws -> EncryptedItem {
        let plaintext = try AESGCMDecryptor(key: oldKey.key.data).decrypt(
            message: .init(ciphertext: item.data, authenticationTag: item.authentication),
            iv: item.encryptionIV,
        )
        let iv = KeyData<32>.random()
        let encrypted = try AESGCMEncryptor(key: newKey.key.data).encrypt(plaintext: plaintext, iv: iv.data)
        return EncryptedItem(
            version: item.version,
            title: item.title,
            data: encrypted.ciphertext,
            authentication: encrypted.authenticationTag,
            encryptionIV: iv.data,
            keygenSalt: newKey.salt,
            keygenSignature: newKey.keyDervier.rawValue,
        )
    }
}
