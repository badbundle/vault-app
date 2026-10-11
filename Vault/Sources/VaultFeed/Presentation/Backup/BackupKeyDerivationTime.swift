import Foundation
import VaultKeygen

/// How long deriving a backup's key can take on the slowest iPhone Vault runs on, for the message shown while it
/// does: setting a backup password, or restoring a backup.
public enum BackupKeyDerivationTime: Equatable, Sendable {
    /// v2's Argon2id alone, which takes about 14 seconds on an iPhone 11.
    case upToAMinute
    /// A derivation from before v2, alone or carried on with v2's, whose PBKDF2 and scrypt take minutes on an older
    /// iPhone. Also what's said for a derivation Vault doesn't know.
    case upToThreeMinutes

    /// For a key derived with `signature`, or one Vault doesn't know, if `nil`.
    public init(signature: VaultKeyDeriver.Signature?) {
        switch signature {
        case .backupSecureV2, .backupFastV2:
            self = .upToAMinute
        case .backupSecureV1, .backupFastV1, .backupSecureV1ThenV2, .backupFastV1ThenV2, .itemSecureV1, .itemFastV1,
             .itemSecureV2, .itemFastV2, .testing, .failing, nil:
            self = .upToThreeMinutes
        }
    }
}
