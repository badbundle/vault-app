internal import CryptoSwift
import Foundation

/// AES-GCM decryption engine.
///
/// Ciphertext and the authentication tag are used to decrypt and validate the message.
/// No padding is used for AES-GCM.
public struct AESGCMDecryptor: Decryptor {
    public typealias Message = AESGCMEncryptedMessage

    private let key: Data

    public init(key: Data) {
        self.key = key
    }

    /// - Parameter ciphertext: The encrypted message.
    /// - Parameter tag: AES-GCM authentication tag that verifies the message
    public func decrypt(message: Message, iv: Data) throws -> Data {
        let gcm = GCM(iv: iv.byteArray, authenticationTag: message.authenticationTag.byteArray, mode: .detached)
        let aes = try AES(key: key.byteArray, blockMode: gcm, padding: .noPadding)
        if message.ciphertext.isEmpty {
            return Data()
        }
        let plaintextBytes = try aes.decrypt(message.ciphertext.byteArray)
        return Data(plaintextBytes)
    }
}
