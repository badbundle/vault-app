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

    @Test
    func handleImportFromEncryptedVault_validGivesSuccess() async {
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        let payload = anyVaultApplicationPayload()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            payload
        }
        let sut = makeSUT(
            existingBackupPassword: anyBackupPassword(),
            encryptedVaultDecoder: encryptedVaultDecoder,
        )

        await sut.handleImport(fromEncryptedVault: anyEncryptedVault())

        switch sut.payloadState {
        case let .ready(readyPayload, _):
            #expect(readyPayload == payload)
        default:
            Issue.record("Expected .ready but got \(sut.payloadState)")
        }
        #expect(sut.importState == .notStarted)
    }

    @Test
    func handleImportFromEncryptedVault_failedToDecrypt() async {
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            throw TestError()
        }
        let sut = makeSUT(
            existingBackupPassword: anyBackupPassword(),
            encryptedVaultDecoder: encryptedVaultDecoder,
        )

        await sut.handleImport(fromEncryptedVault: anyEncryptedVault())

        #expect(sut.payloadState.isError)
        #expect(sut.importState == .notStarted)
    }

    @Test
    func handleImportFromEncryptedVault_noExistingPasswordPromptsForDifferentPassword() async {
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            anyVaultApplicationPayload()
        }
        let sut = makeSUT(
            existingBackupPassword: nil,
            encryptedVaultDecoder: encryptedVaultDecoder,
        )
        let encryptedVault = anyEncryptedVault()

        await sut.handleImport(fromEncryptedVault: encryptedVault)

        #expect(sut.payloadState == .needsPasswordEntry(encryptedVault))
        #expect(sut.importState == .notStarted)
    }

    @Test
    func handleImportFromEncryptedVault_wrongDecryptionPasswordPromptsForDifferentPassword() async {
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            throw EncryptedVaultDecoderError.decryption
        }
        let sut = makeSUT(
            existingBackupPassword: anyBackupPassword(),
            encryptedVaultDecoder: encryptedVaultDecoder,
        )
        let encryptedVault = anyEncryptedVault()

        await sut.handleImport(fromEncryptedVault: encryptedVault)

        #expect(sut.payloadState == .needsPasswordEntry(encryptedVault))
        #expect(sut.importState == .notStarted)
    }

    @Test
    func cancelPasswordEntry_clearsPendingPromptSoItCanBeShownAgain() async {
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            anyVaultApplicationPayload()
        }
        let sut = makeSUT(
            existingBackupPassword: nil,
            encryptedVaultDecoder: encryptedVaultDecoder,
        )
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
    func handleImportFromPDF_validExtractionGivesSuccess() async throws {
        let backupPDFDetatcher = VaultBackupPDFDetatcherMock()
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        let payload = anyVaultApplicationPayload()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            payload
        }
        let sut = makeSUT(
            existingBackupPassword: anyBackupPassword(),
            encryptedVaultDecoder: encryptedVaultDecoder,
            backupPDFDetatcher: backupPDFDetatcher,
        )
        backupPDFDetatcher.detachEncryptedVaultHandler = { _ in
            anyEncryptedVault()
        }
        let pdfData = try anyPDFData()

        await sut.handleImport(fromPDF: .success(pdfData))

        switch sut.payloadState {
        case let .ready(readyPayload, _):
            #expect(readyPayload == payload)
        default:
            Issue.record("Expected .ready but got \(sut.payloadState)")
        }
        #expect(sut.importState == .notStarted)
    }

    @Test
    func handleImportFromPDF_failedToDecrypt() async throws {
        let backupPDFDetatcher = VaultBackupPDFDetatcherMock()
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            throw TestError()
        }
        let sut = makeSUT(
            existingBackupPassword: anyBackupPassword(),
            encryptedVaultDecoder: encryptedVaultDecoder,
            backupPDFDetatcher: backupPDFDetatcher,
        )
        backupPDFDetatcher.detachEncryptedVaultHandler = { _ in
            anyEncryptedVault()
        }
        let pdfData = try anyPDFData()

        await sut.handleImport(fromPDF: .success(pdfData))

        #expect(sut.payloadState.isError)
        #expect(sut.importState == .notStarted)
    }

    @Test
    func handleImportFromPDF_noExistingPasswordPromptsForDifferentPassword() async throws {
        let backupPDFDetatcher = VaultBackupPDFDetatcherMock()
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            anyVaultApplicationPayload()
        }
        let sut = makeSUT(
            existingBackupPassword: nil,
            encryptedVaultDecoder: encryptedVaultDecoder,
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
    }

    @Test
    func handleImportFromPDF_wrongDecryptionPasswordPromptsForDifferentPassword() async throws {
        let backupPDFDetatcher = VaultBackupPDFDetatcherMock()
        let encryptedVaultDecoder = EncryptedVaultDecoderMock()
        encryptedVaultDecoder.decryptAndDecodeHandler = { _, _ in
            throw EncryptedVaultDecoderError.decryption
        }
        let sut = makeSUT(
            existingBackupPassword: anyBackupPassword(),
            encryptedVaultDecoder: encryptedVaultDecoder,
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
        existingBackupPassword: DerivedEncryptionKey? = nil,
        encryptedVaultDecoder: EncryptedVaultDecoderMock = EncryptedVaultDecoderMock(),
        backupPDFDetatcher: VaultBackupPDFDetatcherMock = VaultBackupPDFDetatcherMock(),
    ) -> BackupImportFlowViewModel {
        BackupImportFlowViewModel(
            importContext: importContext,
            dataModel: dataModel,
            existingBackupPassword: existingBackupPassword,
            encryptedVaultDecoder: encryptedVaultDecoder,
            backupPDFDetatcher: backupPDFDetatcher,
        )
    }
}
