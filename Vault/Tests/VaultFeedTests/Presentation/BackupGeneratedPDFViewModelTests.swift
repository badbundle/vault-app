import Foundation
import PDFKit
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

@MainActor
struct BackupGeneratedPDFViewModelTests {
    @Test
    func init_isNotSavedAndLogsNothing() {
        let logger = BackupEventLoggerMock()
        let sut = makeSUT(backupEventLogger: logger)

        #expect(!sut.isSaved)
        #expect(logger.exportedToPDFCallCount == 0)
    }

    @Test
    func shareSheetFinished_completedMarksSavedAndLogsBackup() {
        let logger = BackupEventLoggerMock()
        let pdf = anyGeneratedPDF(createdDate: Date(timeIntervalSince1970: 1234))
        let sut = makeSUT(pdf: pdf, backupEventLogger: logger)

        sut.shareSheetFinished(completed: true)

        #expect(sut.isSaved)
        #expect(logger.exportedToPDFArgValues.map(\.0) == [Date(timeIntervalSince1970: 1234)])
        #expect(logger.exportedToPDFArgValues.map(\.1) == [pdf.dataHash])
    }

    /// Closing the share sheet without saving leaves nothing backed up, so nothing is logged.
    @Test
    func shareSheetFinished_cancelledStaysUnsavedAndLogsNothing() {
        let logger = BackupEventLoggerMock()
        let sut = makeSUT(backupEventLogger: logger)

        sut.shareSheetFinished(completed: false)

        #expect(!sut.isSaved)
        #expect(logger.exportedToPDFCallCount == 0)
    }

    @Test
    func shareSheetFinished_savingAnotherCopyLogsOnlyOnce() {
        let logger = BackupEventLoggerMock()
        let sut = makeSUT(backupEventLogger: logger)

        sut.shareSheetFinished(completed: true)
        sut.shareSheetFinished(completed: false)
        sut.shareSheetFinished(completed: true)

        #expect(sut.isSaved)
        #expect(logger.exportedToPDFCallCount == 1)
    }
}

// MARK: - Helpers

extension BackupGeneratedPDFViewModelTests {
    private func makeSUT(
        pdf: BackupCreatePDFViewModel.GeneratedPDF? = nil,
        backupEventLogger: BackupEventLoggerMock = BackupEventLoggerMock(),
    ) -> BackupGeneratedPDFViewModel {
        BackupGeneratedPDFViewModel(pdf: pdf ?? anyGeneratedPDF(), backupEventLogger: backupEventLogger)
    }

    private func anyGeneratedPDF(createdDate: Date = Date(timeIntervalSince1970: 100)) -> BackupCreatePDFViewModel
        .GeneratedPDF
    {
        BackupCreatePDFViewModel.GeneratedPDF(
            document: PDFDocument(),
            diskURL: URL(fileURLWithPath: "/tmp/backup.pdf"),
            size: .a4,
            dataHash: .init(value: Data(repeating: 0xAB, count: 32)),
            createdDate: createdDate,
        )
    }
}
