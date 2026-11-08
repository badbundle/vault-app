import Combine
import Foundation
import TestHelpers
import Testing
import VaultBackup
import VaultKeygen
@testable import VaultFeed

@MainActor
struct BackupCheckViewModelTests {
    @Test @LeakTracked
    func init_hasNothingToCheck() throws {
        let sut = makeSUT()

        #expect(sut.state == .none)
    }

    @Test @LeakTracked
    func checkPDF_asksForThePassword() async throws {
        let detatcher = VaultBackupPDFDetatcherMock()
        let encryptedVault = anyEncryptedVault()
        detatcher.detachEncryptedVaultHandler = { _ in encryptedVault }
        let sut = makeSUT(backupPDFDetatcher: detatcher)

        try await sut.check(pdf: .success(anyPDFData()))

        #expect(sut.state == .needsPasswordEntry(encryptedVault))
    }

    @Test @LeakTracked
    func checkPDF_fileThatCantBeReadFails() async throws {
        let sut = makeSUT()

        await sut.check(pdf: .failure(TestError()))

        #expect(sut.state.isError)
    }

    @Test @LeakTracked
    func checkPDF_dataThatIsntAPDFFails() async throws {
        let sut = makeSUT()

        await sut.check(pdf: .success(Data()))

        #expect(sut.state.isError)
    }

    @Test @LeakTracked
    func checkPDF_noBackupInThePDFFails() async throws {
        let detatcher = VaultBackupPDFDetatcherMock()
        detatcher.detachEncryptedVaultHandler = { _ in throw TestError() }
        let sut = makeSUT(backupPDFDetatcher: detatcher)

        try await sut.check(pdf: .success(anyPDFData()))

        #expect(sut.state.isError)
    }

    @Test @LeakTracked
    func checkEncryptedVault_asksForThePassword() throws {
        let sut = makeSUT()
        let encryptedVault = anyEncryptedVault()

        sut.check(encryptedVault: encryptedVault)

        #expect(sut.state == .needsPasswordEntry(encryptedVault))
    }

    /// The password screen decrypts and decodes the whole backup, and only then does the check say it opened.
    @Test @LeakTracked
    func passwordScreen_decodingTheBackup_opensIt() async throws {
        let sut = makeSUT()
        let decoder = EncryptedVaultDecoderMock()
        decoder.decryptAndDecodeHandler = { _, _ in anyVaultApplicationPayload() }
        sut.check(encryptedVault: anyEncryptedVault())

        await enterPassword(into: sut, decoder: decoder)

        #expect(sut.state.isOpened)
        #expect(decoder.decryptAndDecodeCallCount == 1)
    }

    @Test(arguments: [EncryptedVaultDecoderError.decryption, .decoding, .incompatibleVersion]) @LeakTracked
    func passwordScreen_backupThatCantBeReadInFull_doesNotOpen(error: EncryptedVaultDecoderError) async throws {
        let sut = makeSUT()
        let decoder = EncryptedVaultDecoderMock()
        decoder.decryptAndDecodeHandler = { _, _ in throw error }
        let encryptedVault = anyEncryptedVault()
        sut.check(encryptedVault: encryptedVault)

        await enterPassword(into: sut, decoder: decoder)

        // It stays on the password, which says what went wrong.
        #expect(sut.state == .needsPasswordEntry(encryptedVault))
    }

    @Test @LeakTracked
    func backupDidOpen_againIsAChangeTheUISees() throws {
        let sut = makeSUT()
        sut.backupDidOpen()
        let first = sut.state

        sut.backupDidOpen()

        #expect(sut.state.isOpened)
        #expect(sut.state != first)
    }

    @Test @LeakTracked
    func cancelPasswordEntry_clearsThePromptSoTheSameBackupCanBeCheckedAgain() throws {
        let sut = makeSUT()
        let encryptedVault = anyEncryptedVault()
        sut.check(encryptedVault: encryptedVault)

        sut.cancelPasswordEntry()

        #expect(sut.state == .none)

        sut.check(encryptedVault: encryptedVault)

        #expect(sut.state == .needsPasswordEntry(encryptedVault))
    }

    /// The password sheet closes after the backup opens, which mustn't clear what the check found.
    @Test @LeakTracked
    func cancelPasswordEntry_afterTheBackupOpened_leavesItOpened() throws {
        let sut = makeSUT()
        sut.check(encryptedVault: anyEncryptedVault())
        sut.backupDidOpen()

        sut.cancelPasswordEntry()

        #expect(sut.state.isOpened)
    }

    @Test @LeakTracked
    func clearResult_afterAnError_goesBackToAskingForABackup() async throws {
        let sut = makeSUT()
        await sut.check(pdf: .failure(TestError()))

        sut.clearResult()

        #expect(sut.state == .none)
    }

    @Test @LeakTracked
    func clearResult_afterTheBackupOpened_goesBackToAskingForABackup() throws {
        let sut = makeSUT()
        sut.backupDidOpen()

        sut.clearResult()

        #expect(sut.state == .none)
    }

    @Test @LeakTracked
    func clearResult_leavesAPendingPasswordPromptAlone() throws {
        let sut = makeSUT()
        let encryptedVault = anyEncryptedVault()
        sut.check(encryptedVault: encryptedVault)

        sut.clearResult()

        #expect(sut.state == .needsPasswordEntry(encryptedVault))
    }
}

// MARK: - Helpers

extension BackupCheckViewModelTests {
    private func makeSUT(
        backupPDFDetatcher: any VaultBackupPDFDetatcher = VaultBackupPDFDetatcherMock(),
    ) -> BackupCheckViewModel {
        trackForMemoryLeaks(BackupCheckViewModel(backupPDFDetatcher: backupPDFDetatcher))
    }

    /// Types a password into the password screen the check asks for, and tells the check once the backup opens, as
    /// Check a Backup's views do.
    private func enterPassword(into sut: BackupCheckViewModel, decoder: EncryptedVaultDecoderMock) async {
        guard case let .needsPasswordEntry(encryptedVault) = sut.state else {
            Issue.record("Expected the check to ask for the password, got \(sut.state)")
            return
        }
        let decrypted = PassthroughSubject<VaultApplicationPayload, Never>()
        var didOpen = false
        let subscription = decrypted.sink { _ in didOpen = true }
        defer { subscription.cancel() }
        let passwordScreen = BackupKeyDecryptorViewModel(
            encryptedVault: encryptedVault,
            keyDeriverFactory: .testing,
            encryptedVaultDecoder: decoder,
            decryptedVaultSubject: decrypted,
        )
        passwordScreen.enteredPassword = "password"
        await passwordScreen.attemptDecryption()
        if didOpen {
            sut.backupDidOpen()
        }
    }
}
