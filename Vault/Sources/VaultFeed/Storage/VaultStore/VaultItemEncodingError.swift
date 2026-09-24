import Foundation

public enum VaultItemEncodingError: Error, Sendable {
    /// A decrypted recovery phrase was passed for storage. Recovery phrases must be encrypted before they are
    /// persisted or backed up.
    case plaintextRecoveryPhraseNotPersistable
}
