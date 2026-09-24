import Foundation
import VaultBackup
import VaultCore
import VaultKeygen

/// From an application-level vault, create the encrypted vault.
public final class EncryptedVaultEncoder {
    private let clock: any EpochClock
    private let backupPassword: DerivedEncryptionKey

    public init(clock: any EpochClock, backupPassword: DerivedEncryptionKey) {
        self.clock = clock
        self.backupPassword = backupPassword
    }

    public func encryptAndEncode(payload: VaultApplicationPayload) throws -> EncryptedVault {
        let encryptionKey = try backupPassword.newVaultKeyWithRandomIV()
        let backupEncoder = VaultBackupEncryptor(
            clock: clock,
            key: encryptionKey,
            keygenSalt: backupPassword.salt,
            keygenSignature: backupPassword.keyDervier.rawValue,
            paddingMode: .random,
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
        )
    }
}
