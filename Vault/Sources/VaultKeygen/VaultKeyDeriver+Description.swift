import CryptoEngine
import Foundation

extension VaultKeyDeriver.Signature {
    /// How a key made this way is derived from its password, in a line, such as "Argon2id, 512 MiB, 32 passes,
    /// 4 lanes": what Check a Backup says the backup's key took.
    ///
    /// Argon2id's numbers come from the parameters the derivation runs with, so they can't drift from it. `nil` for
    /// the test derivations.
    public var derivationDescription: String? {
        let v1Backup = "PBKDF2, HKDF and scrypt"
        let v1Item = "scrypt and PBKDF2"
        return switch self {
        case .testing, .failing: nil
        case .backupFastV1, .backupSecureV1: v1Backup
        case .itemFastV1, .itemSecureV1: v1Item
        case .backupFastV2: Self.describe(VaultKeyDeriver.Backup.Fast.v2Parameters)
        case .backupSecureV2: Self.describe(VaultKeyDeriver.Backup.Secure.v2Parameters)
        case .backupFastV1ThenV2: "\(v1Backup), then \(Self.describe(VaultKeyDeriver.Backup.Fast.v2Parameters))"
        case .backupSecureV1ThenV2: "\(v1Backup), then \(Self.describe(VaultKeyDeriver.Backup.Secure.v2Parameters))"
        case .itemFastV2: Self.describe(VaultKeyDeriver.Item.Fast.v2Parameters)
        case .itemSecureV2: Self.describe(VaultKeyDeriver.Item.Secure.v2Parameters)
        }
    }

    private static func describe(_ parameters: Argon2idParameters) -> String {
        "Argon2id, \(parameters.memoryKiB / 1024) MiB, \(parameters.iterations) passes, \(parameters.parallelism) lanes"
    }
}
