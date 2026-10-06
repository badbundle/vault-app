import Combine
import Foundation
import PDFKit
import TestHelpers
import Testing
import VaultBackup
import VaultCore
import VaultKeygen
@testable import VaultFeed
@testable import VaultMac

@MainActor
struct VaultMacBackupTests {
    @Test
    func saver_save_writesThePDFAndLogsItOnce() throws {
        let logger = BackupEventLoggerMock()
        let sut = VaultMacBackupPDFSaver(backupEventLogger: logger)
        let pdf = Self.anyPDF()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try sut.save(pdf, to: url)

        let saved = try #require(PDFDocument(url: url))
        #expect(saved.pageCount == pdf.document.pageCount)
        #expect(logger.exportedToPDFCallCount == 1)
        #expect(logger.exportedToPDFArgValues.first?.backupDate == pdf.createdDate)
    }

    @Test
    func saver_save_whereItCantWrite_throwsAndLogsNothing() {
        let logger = BackupEventLoggerMock()
        let sut = VaultMacBackupPDFSaver(backupEventLogger: logger)
        let pdf = Self.anyPDF()
        let url = URL(filePath: "/nowhere-\(UUID().uuidString)/backup.pdf")

        #expect(throws: VaultMacBackupPDFSaver.Failure.notWritten) {
            try sut.save(pdf, to: url)
        }
        #expect(logger.exportedToPDFCallCount == 0)
    }

    /// Cancelling the print panel isn't a backup.
    @Test
    func saver_printOnPaper_logsOnlyOnceItsPrinted() {
        let logger = BackupEventLoggerMock()
        let pdf = Self.anyPDF()

        let cancelled = VaultMacBackupPDFSaver(backupEventLogger: logger, runPrint: { _ in false })
        #expect(!cancelled.printOnPaper(pdf))
        #expect(logger.exportedToPDFCallCount == 0)

        let printed = VaultMacBackupPDFSaver(backupEventLogger: logger, runPrint: { _ in true })
        #expect(printed.printOnPaper(pdf))
        #expect(logger.exportedToPDFCallCount == 1)
    }

    @Test
    func fileName_isNamedForWhenItWasMade() {
        let pdf = Self.anyPDF()

        let name = BackupPDFTemporaryFiles.fileName(for: pdf)

        #expect(name.hasPrefix("vault-export-"))
        #expect(name.hasSuffix(".pdf"))
        #expect(!name.contains(":"))
    }

    /// A backup saved as the Mac saves it, restored into another vault as the Mac restores it: from the file, with
    /// its password.
    @Test
    func roundTrip_backupSavedOnTheMac_restoresIntoAnotherVault() async throws {
        let (source, sourceStore) = try MacTestVault.make()
        _ = try await sourceStore.insert(item: MacTestItems.code(issuer: "Example").makeWritable())
        _ = try await sourceStore.insert(item: MacTestItems.note(title: "Wi-Fi").makeWritable())
        let pdf = try await Self.makeBackupPDF(dataModel: source)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try VaultMacBackupPDFSaver(backupEventLogger: BackupEventLoggerMock()).save(pdf, to: url)

        let (destination, destinationStore) = try MacTestVault.make()
        try await Self.restore(pdf: Data(contentsOf: url), password: Self.backupPassword, into: destination)

        let restored = try await destinationStore.exportVault(userDescription: "").items
        #expect(try Set(restored.map(\.id)) == Set(await sourceStore.exportVault(userDescription: "").items.map(\.id)))
    }

    /// A backup an iPhone made, from the golden corpus, restores on the Mac as it's restored: from the file, with its
    /// password.
    @Test
    func restore_backupMadeOnAnIPhone_restoresOnTheMac() async throws {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent() // VaultMacTests
            .deletingLastPathComponent() // Tests
            .appending(path: "VaultFeedTests/Fixtures/Backups/pdf-random-padding.pdf")
        let (destination, store) = try MacTestVault.make()

        try await Self.restore(
            pdf: Data(contentsOf: fixture),
            password: "correct horse battery staple",
            into: destination,
        )

        let restored = try await store.exportVault(userDescription: "")
        #expect(restored.items.count == 5)
        #expect(restored.tags.count == 2)
    }
}

extension VaultMacBackupTests {
    static let backupPassword = "correct horse battery staple"

    /// A one-page PDF standing in for a backup, for the tests that only save or print one: making a real one takes
    /// seconds.
    static func anyPDF() -> BackupCreatePDFViewModel.GeneratedPDF {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        return BackupCreatePDFViewModel.GeneratedPDF(
            document: document,
            size: .a4,
            dataHash: Digest<VaultApplicationPayload>.SHA256(value: Data(repeating: 1, count: 32)),
            createdDate: Date(timeIntervalSince1970: 100),
            vaultToken: 0,
        )
    }

    /// A backup PDF of `dataModel`'s vault, made as Keep a Backup makes one.
    static func makeBackupPDF(dataModel: VaultDataModel? = nil) async throws -> BackupCreatePDFViewModel.GeneratedPDF {
        let dataModel = try dataModel ?? MacTestVault.make().0
        let key = try VaultKeyDeriverFactoryImpl().makeVaultBackupKeyDeriver()
            .createEncryptionKey(password: backupPassword)
        let viewModel = try BackupCreatePDFViewModel(
            backupPassword: key,
            dataModel: dataModel,
            clock: EpochClockMock(currentTime: 100),
            defaults: .nonPersistent(),
            hintStorage: Defaults.nonPersistent(),
        )
        var generated: BackupCreatePDFViewModel.GeneratedPDF?
        let subscription = viewModel.generatedPDFPublisher().sink { generated = $0 }
        defer { subscription.cancel() }
        await viewModel.createPDF()
        return try #require(generated)
    }

    /// Restores a backup PDF into `dataModel`'s vault as the Mac's Restore page does.
    static func restore(pdf: Data, password: String, into dataModel: VaultDataModel) async throws {
        let flow = BackupImportFlowViewModel(importContext: .toEmptyVault, dataModel: dataModel)
        await flow.handleImport(fromPDF: .success(pdf))
        guard case let .needsPasswordEntry(vault) = flow.payloadState else {
            Issue.record("Expected the flow to ask for the password, got \(flow.payloadState)")
            return
        }
        let decrypted = PassthroughSubject<VaultApplicationPayload, Never>()
        var received: VaultApplicationPayload?
        let subscription = decrypted.sink { received = $0 }
        defer { subscription.cancel() }
        let passwordEntry = BackupKeyDecryptorViewModel(
            encryptedVault: vault,
            keyDeriverFactory: VaultKeyDeriverFactoryImpl(),
            encryptedVaultDecoder: EncryptedVaultDecoderImpl(),
            decryptedVaultSubject: decrypted,
        )
        passwordEntry.enteredPassword = password
        await passwordEntry.attemptDecryption()
        try flow.handleVaultDecoded(payload: #require(received))
        guard case let .ready(payload, _) = flow.payloadState else {
            Issue.record("Expected a backup ready to import, got \(flow.payloadState)")
            return
        }
        await flow.importPayload(payload: payload)
        #expect(flow.importState == .success)
    }
}
