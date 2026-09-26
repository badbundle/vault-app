import Foundation
import PDFKit
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

@MainActor
struct BackupGeneratedPDFViewModelTests {
    @Test
    func init_isNotSavedAndLogsNothing() throws {
        let logger = BackupEventLoggerMock()
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(backupEventLogger: logger, directory: directory.url)

        #expect(!sut.isSaved)
        #expect(sut.fileBeingShared == nil)
        #expect(logger.exportedToPDFCallCount == 0)
        #expect(try directory.contents() == [])
    }

    /// The PDF is only written to a file when the user asks to save it, for the share sheet to share.
    @Test
    func share_writesFileToShare() throws {
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(pdf: anyGeneratedPDF(pageCount: 2), directory: directory.url)

        sut.share()

        let file = try #require(sut.fileBeingShared)
        #expect(file.deletingLastPathComponent().standardizedFileURL == directory.url.standardizedFileURL)
        #expect(PDFDocument(url: file)?.pageCount == 2)
        #expect(sut.shareError == nil)
    }

    @Test
    func share_failingToWriteSetsErrorAndSharesNothing() {
        let missingDirectory = URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")
        let sut = makeSUT(directory: missingDirectory)

        sut.share()

        #expect(sut.fileBeingShared == nil)
        #expect(sut.shareError != nil)
    }

    @Test
    func shareSheetFinished_completedMarksSavedLogsBackupAndDeletesFile() throws {
        let logger = BackupEventLoggerMock()
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let pdf = anyGeneratedPDF(createdDate: Date(timeIntervalSince1970: 1234))
        let sut = makeSUT(pdf: pdf, backupEventLogger: logger, directory: directory.url)
        sut.share()

        sut.shareSheetFinished(completed: true)

        #expect(sut.isSaved)
        #expect(logger.exportedToPDFArgValues.map(\.0) == [Date(timeIntervalSince1970: 1234)])
        #expect(logger.exportedToPDFArgValues.map(\.1) == [pdf.dataHash])
        #expect(sut.fileBeingShared == nil)
        #expect(try directory.contents() == [])
    }

    /// Closing the share sheet without saving leaves nothing backed up, so nothing is logged, and the file
    /// goes too.
    @Test
    func shareSheetFinished_cancelledStaysUnsavedLogsNothingAndDeletesFile() throws {
        let logger = BackupEventLoggerMock()
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(backupEventLogger: logger, directory: directory.url)
        sut.share()

        sut.shareSheetFinished(completed: false)

        #expect(!sut.isSaved)
        #expect(logger.exportedToPDFCallCount == 0)
        #expect(sut.fileBeingShared == nil)
        #expect(try directory.contents() == [])
    }

    @Test
    func share_afterFinishingWritesTheFileAgain() throws {
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(directory: directory.url)
        sut.share()
        sut.shareSheetFinished(completed: false)

        sut.share()

        let file = try #require(sut.fileBeingShared)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test
    func shareSheetFinished_savingAnotherCopyLogsOnlyOnce() throws {
        let logger = BackupEventLoggerMock()
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(backupEventLogger: logger, directory: directory.url)

        for completed in [true, false, true] {
            sut.share()
            sut.shareSheetFinished(completed: completed)
        }

        #expect(sut.isSaved)
        #expect(logger.exportedToPDFCallCount == 1)
        #expect(try directory.contents() == [])
    }
}

// MARK: - Helpers

extension BackupGeneratedPDFViewModelTests {
    private func makeSUT(
        pdf: BackupCreatePDFViewModel.GeneratedPDF = anyGeneratedPDF(),
        backupEventLogger: BackupEventLoggerMock = BackupEventLoggerMock(),
        directory: URL,
    ) -> BackupGeneratedPDFViewModel {
        BackupGeneratedPDFViewModel(
            pdf: pdf,
            backupEventLogger: backupEventLogger,
            files: BackupPDFTemporaryFiles(fileManager: .default, directory: directory),
        )
    }
}
