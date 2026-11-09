import Combine
import Foundation
import Testing
import VaultBackup
import VaultKeygen
@testable import VaultFeed

/// Checking every backup in the corpus, as Check a Backup does: the PDF into the check, its password into the password
/// screen, which decrypts and decodes the whole backup. The auto-backup, which the corpus keeps without its PDF, goes
/// into the check as if it had been read out of the PDF. See `Fixtures/Backups/README.md`.
@MainActor
struct BackupCorpusCheckTests {
    /// Every backup that restores opens with its password, whichever format and key derivation it was made with.
    @Test(arguments: BackupCorpusEntry.backups)
    func backup_opensWithItsPassword(entry: BackupCorpusEntry) async throws {
        let check = BackupCheckViewModel()
        try await start(check, with: entry)

        let passwordScreen = try await enterPassword(BackupCorpus.password, into: check)

        #expect(passwordScreen.decryptionKeyState == .validDecryptionKey)
        #expect(check.state.isOpened)
    }

    @Test
    func pdf_withAWrongPassword_doesNotOpen() async throws {
        let check = BackupCheckViewModel()
        try await start(check, with: .pdfWithRandomPadding)

        let passwordScreen = try await enterPassword(BackupCorpus.password.uppercased(), into: check)

        let encryptedVault = try BackupCorpusEntry.pdfWithRandomPadding.encryptedVault()
        #expect(passwordScreen.decryptionKeyState.isError)
        #expect(check.state == .needsPasswordEntry(encryptedVault))
    }
}

// MARK: - Helpers

extension BackupCorpusCheckTests {
    private func start(_ check: BackupCheckViewModel, with entry: BackupCorpusEntry) async throws {
        switch entry.form {
        case .pdf:
            try await check.check(pdf: .success(entry.data()))
        case .encryptedVault, .qrCodes:
            try check.check(encryptedVault: entry.encryptedVault())
        }
    }

    /// Enters `password` in the password screen the check asks for, and tells the check once the backup opens, as
    /// Check a Backup's views do.
    private func enterPassword(_ password: String, into check: BackupCheckViewModel) async throws
        -> BackupKeyDecryptorViewModel
    {
        guard case let .needsPasswordEntry(encryptedVault) = check.state else {
            Issue.record("Expected the check to ask for the password, got \(check.state)")
            throw CheckDidNotAskForThePassword()
        }
        let decrypted = PassthroughSubject<VaultApplicationPayload, Never>()
        var didOpen = false
        let subscription = decrypted.sink { _ in didOpen = true }
        defer { subscription.cancel() }
        let passwordScreen = BackupKeyDecryptorViewModel(
            encryptedVault: encryptedVault,
            keyDeriverFactory: VaultKeyDeriverFactoryImpl(),
            encryptedVaultDecoder: EncryptedVaultDecoderImpl(),
            decryptedVaultSubject: decrypted,
        )
        passwordScreen.enteredPassword = password
        await passwordScreen.attemptDecryption()
        if didOpen {
            check.backupDidOpen()
        }
        return passwordScreen
    }

    private struct CheckDidNotAskForThePassword: Error {}
}
