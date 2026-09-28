import Foundation
import Testing
import VaultCore
import VaultKeygen
@testable import VaultBackup

/// Makes the backup fixtures that aren't in `Fixtures/` yet, with the app's own code, and writes them into the source
/// tree. It only runs when it's asked to:
///
/// ```
/// TEST_RUNNER_VAULT_RECORD_FIXTURES=1 xcodebuild test … -only-testing:VaultBackupTests/BackupFixtureRecorder
/// ```
///
/// It never replaces a fixture that's there. It prints the values the code chose at random that the tests check, to
/// be copied into the fixture's definition. See `Fixtures/README.md`.
@Suite(.enabled(if: GoldenFixture.isRecording))
struct BackupFixtureRecorder {
    /// Encrypts the backup as `EncryptedVaultEncoder` does when the app saves one: with a key derived from the backup
    /// password with a new salt, a random IV, and the fixture's padding.
    @Test(arguments: BackupFixture.all)
    func recordIfMissing(fixture: BackupFixture) throws {
        guard !GoldenFixture.isRecorded(fixture.name) else { return }
        let backupPassword = try VaultKeyDeriver.Backup.Fast.v1.createEncryptionKey(password: BackupFixture.password)
        let encryptor = try VaultBackupEncryptor(
            clock: EpochClockMock(currentTime: BackupFixture.created.timeIntervalSince1970),
            key: backupPassword.newVaultKeyWithRandomIV(),
            keygenSalt: backupPassword.salt,
            keygenSignature: backupPassword.keyDervier.rawValue,
            paddingMode: fixture.padding == .toFixedSize ? .toFixedSize(minimum: 32 * 1024) : .random,
        )

        let vault = try encryptor.encryptBackupPayload(
            items: BackupFixture.items,
            tags: BackupFixture.tags,
            userDescription: BackupFixture.userDescription,
        )

        try GoldenFixture.record(EncryptedVaultCoder().encode(vault: vault), named: fixture.name)
        // Only when recording, which has to be asked for.
        // swiftlint:disable:next no_direct_standard_out_logs
        print("Recorded \(fixture.name). Copy into BackupFixture: encrypted length \(vault.data.count)")
    }
}
