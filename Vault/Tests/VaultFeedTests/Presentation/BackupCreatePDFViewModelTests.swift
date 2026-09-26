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
    ) throws -> BackupCreatePDFViewModel {
        let defaults = try testUserDefaults()
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
            defaults: Defaults(userDefaults: defaults),
            fileManager: FileManager(),
        )
    }
}
