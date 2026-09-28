internal import CryptoSwift
import Foundation

/// AES-GCM decryption engine.
///
/// Ciphertext and the authentication tag are used to decrypt and validate the message.
/// No padding is used for AES-GCM.
public struct AESGCMDecryptor: Decryptor {
    public typealias Message = AESGCMEncryptedMessage

    private let key: Data

    public enum DecryptionError: Error, Equatable {
        /// The authentication tag isn't the full length that `AESGCMEncryptor` makes.
        case invalidAuthenticationTagLength
        /// The authentication tag doesn't match the message.
        case authenticationFailed
    }

    /// The length of every tag `AESGCMEncryptor` makes, and the only length accepted.
    public static let authenticationTagLength = 16

    public init(key: Data) {
        self.key = key
    }

    /// - Parameter ciphertext: The encrypted message.
    /// - Parameter tag: AES-GCM authentication tag that verifies the message
    public func decrypt(message: Message, iv: Data) throws -> Data {
        guard message.authenticationTag.count == Self.authenticationTagLength else {
            throw DecryptionError.invalidAuthenticationTagLength
        }
        if message.ciphertext.isEmpty {
            return try decryptEmpty(message: message, iv: iv)
        }
        let gcm = GCM(iv: iv.byteArray, authenticationTag: message.authenticationTag.byteArray, mode: .detached)
        let aes = try AES(key: key.byteArray, blockMode: gcm, padding: .noPadding)
        let plaintextBytes = try aes.decrypt(message.ciphertext.byteArray)
        return Data(plaintextBytes)
    }

    /// An empty message is authentic when its tag is the one that sealing an empty message under the same key and IV
    /// makes.
    private func decryptEmpty(message: Message, iv: Data) throws -> Data {
        let expected = try AESGCMEncryptor(key: key).encrypt(plaintext: Data(), iv: iv).authenticationTag
        guard expected.count == message.authenticationTag.count else {
            throw DecryptionError.authenticationFailed
        }
        let difference = zip(expected, message.authenticationTag).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard difference == 0 else {
            throw DecryptionError.authenticationFailed
        }
        return Data()
    }
}
