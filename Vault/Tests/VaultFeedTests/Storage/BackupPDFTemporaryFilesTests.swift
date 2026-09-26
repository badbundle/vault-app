import Foundation
import PDFKit
import Testing
@testable import VaultFeed

struct BackupPDFTemporaryFilesTests {
    @Test
    func write_writesThePDFNamedForWhenItWasMade() throws {
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(directory: directory.url)
        let pdf = anyGeneratedPDF(pageCount: 2, createdDate: Date(timeIntervalSince1970: 100))

        let url = try sut.write(pdf)

        let timestamp = VaultDateFormatter(timezone: .current).formatForFileName(date: Date(timeIntervalSince1970: 100))
        #expect(url == directory.url.appending(path: "vault-export-\(timestamp).pdf"))
        #expect(PDFDocument(url: url)?.pageCount == 2)
    }

    @Test
    func write_throwsIfItCantWrite() throws {
        let missingDirectory = URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")
        let sut = makeSUT(directory: missingDirectory)

        #expect(throws: BackupPDFTemporaryFiles.Error.notWritten) {
            try sut.write(anyGeneratedPDF())
        }
    }

    @Test
    func delete_deletesTheFile() throws {
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(directory: directory.url)
        let url = try sut.write(anyGeneratedPDF())

        sut.delete(url)

        #expect(try directory.contents() == [])
    }

    @Test
    func delete_doesNothingIfAlreadyGone() throws {
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(directory: directory.url)

        sut.delete(directory.url.appending(path: "vault-export-gone.pdf"))

        #expect(try directory.contents() == [])
    }

    /// Clears backup PDFs this type wrote and ones earlier versions of the app left, but nothing else in the
    /// directory.
    @Test
    func deleteAll_deletesOnlyBackupPDFs() throws {
        let directory = try TemporaryTestDirectory()
        defer { directory.remove() }
        let sut = makeSUT(directory: directory.url)
        _ = try sut.write(anyGeneratedPDF(createdDate: Date(timeIntervalSince1970: 100)))
        _ = try sut.write(anyGeneratedPDF(createdDate: Date(timeIntervalSince1970: 200)))
        for name in ["vault-export-2026-09-26T19-17-17.8_01-00.pdf", "other.pdf", "vault-export-notes.txt"] {
            try Data("x".utf8).write(to: directory.url.appending(path: name))
        }

        sut.deleteAll()

        #expect(try directory.contents() == ["other.pdf", "vault-export-notes.txt"])
    }

    @Test
    func deleteAll_doesNothingIfDirectoryIsMissing() {
        let sut = makeSUT(directory: URL.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)"))

        sut.deleteAll()
    }
}

// MARK: - Helpers

extension BackupPDFTemporaryFilesTests {
    private func makeSUT(directory: URL) -> BackupPDFTemporaryFiles {
        BackupPDFTemporaryFiles(fileManager: .default, directory: directory)
    }
}
