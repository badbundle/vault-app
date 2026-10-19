import Foundation

public enum VaultItemEncodingError: Error, Sendable {
    /// A decrypted recovery phrase was passed for storage. Recovery phrases must be encrypted before they are
    /// persisted or backed up.
    case plaintextRecoveryPhraseNotPersistable
    /// A decrypted private key was passed for storage. Private keys must be encrypted before they are persisted or
    /// backed up.
    case plaintextPrivateKeyNotPersistable
}
