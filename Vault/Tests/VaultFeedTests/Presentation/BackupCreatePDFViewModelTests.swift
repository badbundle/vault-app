import Combine
import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

@MainActor
struct BackupCreatePDFViewModelTests {
    @Test
    func init_hasNoSideEffects() throws {
        let vaultStore = VaultStoreStub()
        let vaultTagStore = VaultTagStoreStub()
        let backupPasswordStore = BackupPasswordStoreMock()
        _ = try makeSUT(vaultStore: vaultStore, vaultTagStore: vaultTagStore, backupPasswordStore: backupPasswordStore)

        #expect(vaultStore.calledMethods == [])
        #expect(vaultTagStore.calledMethods == [])
        #expect(backupPasswordStore.fetchPasswordCallCount == 0)
        #expect(backupPasswordStore.setCallCount == 0)
    }

    @Test
    func init_initialStateIsIdle() throws {
        let sut = try makeSUT()

        #expect(sut.state == .idle)
    }

    @Test
    func createPDF_makesPDFDocument() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "Hello", items: [], tags: [])
        }
        let sut = try makeSUT(vaultStore: vaultStore)

        try await sut.generatedPDFPublisher().expect(valueCount: 1) {
            await sut.createPDF()
        }

        #expect(sut.state == .success)
    }

    @Test
    func createPDF_stampsGeneratedPDFWithCreationDate() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in
            .init(userDescription: "Hello", items: [], tags: [])
        }
        let sut = try makeSUT(vaultStore: vaultStore, clock: EpochClockMock(currentTime: 1234))

        var generated = [BackupCreatePDFViewModel.GeneratedPDF]()
        let cancellable = sut.generatedPDFPublisher().sink { generated.append($0) }
        defer { cancellable.cancel() }

        await sut.createPDF()

        #expect(generated.map(\.createdDate) == [Date(timeIntervalSince1970: 1234)])
    }

    /// Each vault has its own hint, so no vault shows or prints another's.
    @Test
    func init_showsTheOpenVaultsHint() throws {
        let hints = VaultPDFHints(hints: [3: "The open vault's hint"], vaultToken: 3)

        let sut = try makeSUT(hintStorage: hints)

        #expect(sut.userHint == "The open vault's hint")
    }

    /// The hint is printed in plain text, so nothing is printed unless the user writes one.
    @Test
    func init_withoutAHint_startsEmpty() throws {
        let sut = try makeSUT(hintStorage: VaultPDFHints(hints: [:], vaultToken: 3))

        #expect(sut.userHint == "")
    }

    /// A PDF made with the text the hint used to start with saved it as the hint, but the user never wrote it.
    @Test
    func init_withTheFormerDefaultSaved_startsEmpty() throws {
        let formerDefault =
            "This is my description, which is visible in plain text on the vault backup. You can use the Vault app to import this data if you lose access to your device."
        let sut = try makeSUT(hintStorage: VaultPDFHints(hints: [3: formerDefault], vaultToken: 3))

        #expect(sut.userHint == "")
    }

    @Test
    func createPDF_savesTheHintAndStampsThePDFWithTheVault() async throws {
        let hints = VaultPDFHints(hints: [:], vaultToken: 3)
        let sut = try makeSUT(hintStorage: hints)
        sut.userHint = "New hint"
        var generated = [BackupCreatePDFViewModel.GeneratedPDF]()
        let cancellable = sut.generatedPDFPublisher().sink { generated.append($0) }
        defer { cancellable.cancel() }

        await sut.createPDF()

        #expect(hints.hints == [3: "New hint"])
        #expect(generated.map(\.vaultToken) == [3])
    }

    /// Another vault opened after the page did: the hint is the first vault's, so it isn't saved into this one.
    @Test
    func createPDF_afterAnotherVaultOpened_doesNotSaveTheHintThere() async throws {
        let hints = VaultPDFHints(hints: [3: "First vault's hint"], vaultToken: 3)
        let sut = try makeSUT(hintStorage: hints)
        hints.vaultToken = 4

        await sut.createPDF()

        #expect(hints.hints == [3: "First vault's hint"])
    }

    @Test
    func createPDF_errorSetsErrorState() async throws {
        let vaultStore = VaultStoreStub()
        vaultStore.exportVaultHandler = { _ in throw TestError() }
        let sut = try makeSUT(vaultStore: vaultStore)

        try await sut.generatedPDFPublisher().expect(valueCount: 0) {
            await sut.createPDF()
        }

        #expect(sut.state.isError)
    }
}

// MARK: - Helpers

extension BackupCreatePDFViewModelTests {
    @MainActor
    private func makeSUT(
        vaultStore: any VaultStore = VaultStoreStub(),
        vaultTagStore: any VaultTagStore = VaultTagStoreStub(),
        backupPasswordStore: any BackupPasswordStore = BackupPasswordStoreMock(),
        backupPassword: DerivedEncryptionKey = anyBackupPassword(),
        clock: some EpochClock = EpochClockMock(currentTime: 100),
        hintStorage: (any BackupPDFHintStorage)? = nil,
    ) throws -> BackupCreatePDFViewModel {
        let defaults = try Defaults(userDefaults: testUserDefaults())
        return BackupCreatePDFViewModel(
            backupPassword: backupPassword,
            dataModel: VaultDataModel(
                vaultStore: vaultStore,
                vaultTagStore: vaultTagStore,
                vaultImporter: VaultStoreImporterMock(),
                vaultDeleter: VaultStoreDeleterMock(),
                vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
                vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
                backupPasswordStore: backupPasswordStore,
                killphraseKeyStore: StubKillphraseKeyStore(),
                killphraseRehashService: nil,
                searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
                searchPassphraseRehashService: nil,
                backupEventLogger: BackupEventLoggerMock(),
            ),
            clock: clock,
            defaults: defaults,
            hintStorage: hintStorage ?? defaults,
        )
    }
}

/// Each vault's PDF hint, by vault token, and which vault is open.
@MainActor
private final class VaultPDFHints: BackupPDFHintStorage {
    var hints: [Int: String]
    var vaultToken: Int

    init(hints: [Int: String], vaultToken: Int) {
        self.hints = hints
        self.vaultToken = vaultToken
    }

    func pdfUserHint() -> String? {
        hints[vaultToken]
    }

    func savePDFUserHint(_ hint: String, for token: Int) throws {
        guard token == vaultToken else { throw VaultStoreSessionError.locked }
        hints[token] = hint
    }
}
