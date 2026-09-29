import CryptoKit
import Foundation

/// AES-GCM decryption engine, using CryptoKit.
///
/// Ciphertext and the authentication tag are used to decrypt and validate the message.
/// No padding is used for AES-GCM.
///
/// Every kind of encryption in Vault is Apple's. See `docs/export-compliance.md`.
public struct AESGCMDecryptor: Decryptor {
    public typealias Message = AESGCMEncryptedMessage

    private let key: SymmetricKey

    public enum DecryptionError: Error, Equatable {
        /// The authentication tag isn't the full length that `AESGCMEncryptor` makes.
        case invalidAuthenticationTagLength
        /// The authentication tag doesn't match the message.
        case authenticationFailed
    }

    /// The length of every tag `AESGCMEncryptor` makes, and the only length accepted.
    public static let authenticationTagLength = 16

    public init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    /// - Parameter ciphertext: The encrypted message.
    /// - Parameter tag: AES-GCM authentication tag that verifies the message
    public func decrypt(message: Message, iv: Data) throws -> Data {
        guard message.authenticationTag.count == Self.authenticationTagLength else {
            throw DecryptionError.invalidAuthenticationTagLength
        }
        let sealed = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: iv),
            ciphertext: message.ciphertext,
            tag: message.authenticationTag,
        )
        do {
            // Checks the tag before it returns any plaintext, an empty message's included.
            return try AES.GCM.open(sealed, using: key)
        } catch CryptoKitError.authenticationFailure {
            throw DecryptionError.authenticationFailed
        }
    }
}
