import Foundation
import VaultKeygen

/// Indicates that the given item can be encrypted within a vault.
///
/// Allows encoding and decoding to a resilient format.
public protocol VaultItemEncryptable {
    associatedtype EncryptedContainer: VaultItemEncryptedContainer
    init(encryptedContainer: EncryptedContainer)
    func makeEncryptedContainer() throws -> EncryptedContainer
}

public protocol VaultItemEncryptedContainer: Codable {
    /// Identifies the type of item that this is.
    ///
    /// Definitions are in `VaultIdentifiers.Item`
    var itemIdentifier: String { get }
    /// The title, which is also stored unencrypted (as `EncryptedItem.title`) so it can be shown and searched
    /// without the password.
    ///
    /// `VaultItemEncryptor` copies it to `EncryptedItem.title` on every encryption, so it's the single source of the
    /// plaintext title and both copies are always written together. Once decrypted, trust this copy: unlike the
    /// plaintext one, it's authenticated by the encryption.
    var title: String { get }
}
