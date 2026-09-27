import Foundation
import TestHelpers
import Testing
import VaultBackup
import VaultKeygen
@testable import VaultFeed

struct EncryptedVaultEncoderTests {
    @Test
    func encryptAndEncode_usesDifferentIVEachIteration() throws {
        let password = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        // Random padding: filling a fixed size a hundred times over is slow, and it's the IV this is about.
        let sut = EncryptedVaultEncoder(
            clock: EpochClockMock(currentTime: 100),
            backupPassword: password,
            padding: .random,
        )

        var seenData = Set<Data>()
        for _ in 1 ... 100 {
            let payload = VaultApplicationPayload(userDescription: "my backup", items: [], tags: [])
            let backup = try sut.encryptAndEncode(payload: payload)
            defer { seenData.insert(backup.data) }

            #expect(
                seenData.contains(backup.data) == false,
                "A random IV and/or padding should be used each time, resulting in different encrypted payloads",
            )
        }
    }

    /// A saved backup doesn't show how much its vault holds: an empty vault's and one with many items are the same
    /// size (VAULT-75).
    @Test
    func encryptAndEncode_savedBackupsOfDifferentVaults_areTheSameSize() throws {
        let password = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        let sut = EncryptedVaultEncoder(clock: EpochClockMock(currentTime: 100), backupPassword: password)
        let window = (EncryptedVaultEncoder.minimumFixedSize - 16) ... EncryptedVaultEncoder.minimumFixedSize

        let empty = try sut.encryptAndEncode(payload: VaultApplicationPayload(
            userDescription: "my backup",
            items: [],
            tags: [],
        ))
        let full = try sut.encryptAndEncode(payload: VaultApplicationPayload(
            userDescription: "my backup",
            items: (0 ..< 60).map { _ in uniqueVaultItem() },
            tags: [],
        ))

        #expect(window.contains(empty.data.count))
        #expect(window.contains(full.data.count))
    }

    /// A transfer to another device saves nothing, so it's only padded by a random amount, and stays quick to show.
    @Test
    func encryptAndEncode_forATransfer_isPaddedByARandomAmount() throws {
        let password = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        let sut = EncryptedVaultEncoder(
            clock: EpochClockMock(currentTime: 100),
            backupPassword: password,
            padding: .random,
        )

        let backup = try sut.encryptAndEncode(payload: VaultApplicationPayload(
            userDescription: "",
            items: [uniqueVaultItem()],
            tags: [],
        ))

        #expect(backup.data.count < 8 * 1024)
    }

    @Test
    func encryptAndEncode_savedBackup_decodesToTheSameItems() throws {
        let password = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        let sut = EncryptedVaultEncoder(clock: EpochClockMock(currentTime: 100), backupPassword: password)
        let items = (0 ..< 3).map { _ in uniqueVaultItem() }

        let backup = try sut.encryptAndEncode(payload: VaultApplicationPayload(
            userDescription: "my backup",
            items: items,
            tags: [],
        ))
        let decoded = try EncryptedVaultDecoderImpl().decryptAndDecode(key: password.key, encryptedVault: backup)

        #expect(decoded.items.map(\.id) == items.map(\.id))
    }

    @Test
    func encryptAndEncode_createsBackupWithNoItems() throws {
        let salt = Data.random(count: 32)
        let password = DerivedEncryptionKey(key: .random(), salt: salt, keyDervier: .testing)
        let sut = EncryptedVaultEncoder(clock: EpochClockMock(currentTime: 100), backupPassword: password)

        let payload = VaultApplicationPayload(userDescription: "my backup", items: [], tags: [])
        let backup = try sut.encryptAndEncode(payload: payload)

        #expect(backup.encryptionIV.count == 32)
        #expect(backup.keygenSalt == salt)
        #expect(backup.keygenSignature == "vault.keygen.testing")
        #expect(backup.version == "1.0.0")
    }

    @Test
    func encryptAndEncode_createsBackupWithSomeItems() throws {
        let salt = Data.random(count: 32)
        let password = DerivedEncryptionKey(key: .random(), salt: salt, keyDervier: .testing)
        let sut = EncryptedVaultEncoder(clock: EpochClockMock(currentTime: 100), backupPassword: password)

        let payload = VaultApplicationPayload(
            userDescription: "my backup",
            items: [uniqueVaultItem()],
            tags: [VaultItemTag(id: .init(id: UUID()), name: "tag")],
        )
        let backup = try sut.encryptAndEncode(payload: payload)

        #expect(backup.encryptionIV.count == 32)
        #expect(backup.keygenSalt == salt)
        #expect(backup.keygenSignature == "vault.keygen.testing")
        #expect(backup.version == "1.0.0")
    }
}
