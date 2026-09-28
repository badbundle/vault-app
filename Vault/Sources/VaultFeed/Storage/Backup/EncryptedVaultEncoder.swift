import Foundation
import VaultBackup
import VaultCore
import VaultKeygen

/// From an application-level vault, create the encrypted vault.
public final class EncryptedVaultEncoder {
    /// How much the vault is padded before it's encrypted.
    public enum Padding: Equatable, Sendable {
        /// Up to a fixed size, `minimumFixedSize` bytes or the next power of two times it (VAULT-75): for any backup
        /// that's saved, a PDF or an auto-backup. Then a backup doesn't show how much its vault holds, so one found
        /// alongside a duress vault can't show that a bigger vault exists.
        case toFixedSize
        /// By a random amount: for moving to another device, which saves nothing, and whose QR codes each take two
        /// seconds to show.
        case random
    }

    /// About 130 typical items, or roughly 90 of a PDF's QR codes.
    public static let minimumFixedSize = 32 * 1024

    private let clock: any EpochClock
    private let backupPassword: DerivedEncryptionKey
    private let padding: Padding

    public init(clock: any EpochClock, backupPassword: DerivedEncryptionKey, padding: Padding = .toFixedSize) {
        self.clock = clock
        self.backupPassword = backupPassword
        self.padding = padding
    }

    public func encryptAndEncode(payload: VaultApplicationPayload) throws -> EncryptedVault {
        let encryptionKey = try backupPassword.newVaultKeyWithRandomIV()
        let backupEncoder = VaultBackupEncryptor(
            clock: clock,
            key: encryptionKey,
            keygenSalt: backupPassword.salt,
            keygenSignature: backupPassword.keyDervier.rawValue,
            paddingMode: paddingMode,
        )
        let itemEncoder = VaultBackupItemEncoder()
        let tagEncoder = VaultBackupTagEncoder()
        return try backupEncoder.encryptBackupPayload(
            items: payload.items.map {
                try itemEncoder.encode(storedItem: $0)
            },
            tags: payload.tags.map {
                tagEncoder.encode(tag: $0)
            },
            userDescription: payload.userDescription,
            killphraseKeys: payload.killphraseKeys.map(\.data),
            searchPassphraseKeys: payload.searchPassphraseKeys.map(\.data),
        )
    }

    private var paddingMode: VaultBackupEncryptor.PaddingMode {
        switch padding {
        case .toFixedSize: .toFixedSize(minimum: Self.minimumFixedSize)
        case .random: .random
        }
    }
}
