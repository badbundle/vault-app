import CryptoKit
import Foundation

/// AES-GCM encryption engine, using CryptoKit.
///
/// No padding will be used and the authentication tag is always seperate from the ciphertext.
///
/// Every kind of encryption in Vault is Apple's, so Vault can tell App Store Connect it uses no encryption that needs
/// export compliance documentation. Don't encrypt with another library. See `docs/export-compliance.md`.
public struct AESGCMEncryptor: Encryptor {
    public typealias Message = AESGCMEncryptedMessage

    private let key: SymmetricKey

    public init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    /// - Parameter plaintext: the message to be encrypted with AES-GCM.
    /// - Parameter iv: At least 12 bytes. Vault's are 32: GCM derives the counter block from an IV of any other length,
    ///   as its specification says, so a longer one encrypts exactly as it always has.
    public func encrypt(plaintext: Data, iv: Data) throws -> AESGCMEncryptedMessage {
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: iv))
        return AESGCMEncryptedMessage(
            ciphertext: sealed.ciphertext,
            authenticationTag: sealed.tag,
        )
    }
}
