import Foundation
import PDFKit
import TestHelpers
import Testing
import VaultBackup
import VaultKeygen
@testable import VaultFeed

@MainActor
struct BackupImportFlowViewModelTests {
    @Test
    func init_initialState() {
        let sut = makeSUT()

        #expect(sut.payloadState == .none)
        #expect(sut.importState == .notStarted)
        #expect(sut.isImporting == false)
    }

    /// Every backup asks for its password, even one made with the backup password set now: the key this device keeps
    /// only makes backups.
    @Test
    func handleImportFromEncryptedVault_alwaysAsksForThePassword() async {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { anyBackupPassword() }
        let sut = makeSUT(dataModel: anyVaultDataModel(backupPasswordStore: backupPasswordStore))
        let encryptedVault = anyEncryptedVault()

        await sut.handleImport(fromEncryptedVault: encryptedVault)

        #expect(sut.payloadState == .needsPasswordEntry(encryptedVault))
        #expect(sut.importState == .notStarted)
        #expect(backupPasswordStore.fetchPasswordCallCount == 0)
    }

    @Test
    func cancelPasswordEntry_clearsPendingPromptSoItCanBeShownAgain() async {
        let sut = makeSUT()
        let encryptedVault = anyEncryptedVault()
        await sut.handleImport(fromEncryptedVault: encryptedVault)
        #expect(sut.payloadState == .needsPasswordEntry(encryptedVault))

        sut.cancelPasswordEntry()

        // Must not stay on `.needsPasswordEntry`. The state is `Equatable`, so importing the same
        // document again would compare equal and the UI would see no change to react to.
        #expect(sut.payloadState == .none)

        await sut.handleImport(fromEncryptedVault: encryptedVault)

        #expect(sut.payloadState == .needsPasswordEntry(encryptedVault))
    }

    @Test
    func cancelPasswordEntry_doesNotDiscardAnAlreadyDecodedPayload() {
        let sut = makeSUT()
        let payload = anyVaultApplicationPayload()
        sut.handleVaultDecoded(payload: payload)

        sut.cancelPasswordEntry()

        // A dismissal that follows a successful decode must leave the ready payload intact.
        guard case let .ready(readyPayload, _) = sut.payloadState else {
            Issue.record("Expected payload state to remain ready, got \(sut.payloadState)")
            return
        }
        #expect(readyPayload == payload)
    }

    @Test
    func handleImportFromPDF_errorUpdatesPresentationError() async {
        let sut = makeSUT()

        await sut.handleImport(fromPDF: .failure(TestError()))

        #expect(sut.payloadState.isError)
        #expect(sut.importState == .notStarted)
    }

    @Test
    func handleImportFromPDF_invalidPDFDataFails() async {
        let sut = makeSUT()

        await sut.handleImport(fromPDF: .success(Data()))

        #expect(sut.payloadState.isError)
        #expect(sut.importState == .notStarted)
    }

    @Test
    func handleImportFromPDF_asksForThePassword() async throws {
        let backupPDFDetatcher = VaultBackupPDFDetatcherMock()
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { anyBackupPassword() }
        let sut = makeSUT(
            dataModel: anyVaultDataModel(backupPasswordStore: backupPasswordStore),
            backupPDFDetatcher: backupPDFDetatcher,
        )
        let encryptedVault = anyEncryptedVault()
        backupPDFDetatcher.detachEncryptedVaultHandler = { _ in
            encryptedVault
        }
        let pdfData = try anyPDFData()

        await sut.handleImport(fromPDF: .success(pdfData))

        #expect(sut.payloadState == .needsPasswordEntry(encryptedVault))
        #expect(sut.importState == .notStarted)
        #expect(backupPasswordStore.fetchPasswordCallCount == 0)
    }

    @Test
    func handleImportFromPDF_noBackupInThePDFFails() async throws {
        let backupPDFDetatcher = VaultBackupPDFDetatcherMock()
        backupPDFDetatcher.detachEncryptedVaultHandler = { _ in
            throw TestError()
        }
        let sut = makeSUT(backupPDFDetatcher: backupPDFDetatcher)
        let pdfData = try anyPDFData()

        await sut.handleImport(fromPDF: .success(pdfData))

        #expect(sut.payloadState.isError)
        #expect(sut.importState == .notStarted)
    }

    @Test
    func handleVaultDecoded_updatesPayloadStateToReady() {
        let sut = makeSUT()

        let initialPayload = anyVaultApplicationPayload()
        sut.handleVaultDecoded(payload: initialPayload)

        switch sut.payloadState {
        case let .ready(payload, _):
            #expect(payload == initialPayload)
        default:
            Issue.record("Expected .ready but got \(sut.payloadState)")
        }
    }

    @Test
    func importPayload_toEmptyVault() async {
        let importer = VaultStoreImporterMock()
        let dataModel = anyVaultDataModel(vaultImporter: importer)
        let sut = makeSUT(importContext: .toEmptyVault, dataModel: dataModel)

        await sut.importPayload(payload: anyVaultApplicationPayload())

        #expect(sut.importState == .success)
        #expect(importer.importAndMergeVaultCallCount == 1)
        #expect(importer.importAndOverrideVaultCallCount == 0)
    }

    @Test
    func importPayload_merge() async {
        let importer = VaultStoreImporterMock()
        let dataModel = anyVaultDataModel(vaultImporter: importer)
        let sut = makeSUT(importContext: .merge, dataModel: dataModel)

        await sut.importPayload(payload: anyVaultApplicationPayload())

        #expect(sut.importState == .success)
        #expect(importer.importAndMergeVaultCallCount == 1)
        #expect(importer.importAndOverrideVaultCallCount == 0)
    }

    @Test
    func importPayload_override() async {
        let importer = VaultStoreImporterMock()
        let dataModel = anyVaultDataModel(vaultImporter: importer)
        let sut = makeSUT(importContext: .override, dataModel: dataModel)

        await sut.importPayload(payload: anyVaultApplicationPayload())

        #expect(sut.importState == .success)
        #expect(importer.importAndMergeVaultCallCount == 0)
        #expect(importer.importAndOverrideVaultCallCount == 1)
    }
}

// MARK: - Helpers

extension BackupImportFlowViewModelTests {
    @MainActor
    private func makeSUT(
        importContext: BackupImportContext = .toEmptyVault,
        dataModel: VaultDataModel = VaultDataModel(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
            vaultImporter: VaultStoreImporterMock(),
            vaultDeleter: VaultStoreDeleterMock(),
            vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: StubKillphraseKeyStore(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        ),
        backupPDFDetatcher: VaultBackupPDFDetatcherMock = VaultBackupPDFDetatcherMock(),
    ) -> BackupImportFlowViewModel {
        BackupImportFlowViewModel(
            importContext: importContext,
            dataModel: dataModel,
            backupPDFDetatcher: backupPDFDetatcher,
        )
    }
}
