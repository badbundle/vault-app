import Foundation
import Testing
@testable import VaultFeed

struct AutoBackupProviderCoverageTests {
    @Test
    func iCloudDriveProvider_unconfiguredStateIsAvailableForSetup() async {
        let sut = iCloudDriveProvider()

        #expect(sut.id == iCloudDriveProvider.providerID)
        #expect(sut.displayName == "Files")
        #expect(sut.iconSystemName == "folder")
        #expect(await sut.folderDisplayName == nil)
        #expect(await sut.isConfigured == false)
        #expect(await sut.configurationSummary == nil)
        #expect(await sut.isAvailable)
        #expect(await sut.configurationData != nil)
    }

    @Test
    func iCloudDriveProvider_restoresAndClearsConfiguration() async throws {
        let sut = iCloudDriveProvider()
        let config = iCloudDriveProviderConfiguration(
            folderBookmark: Data([0, 1, 2]),
            folderDisplayName: "Backups",
        )
        let data = try JSONEncoder().encode(config)

        try await sut.restoreConfiguration(from: data)

        #expect(await sut.isConfigured)
        #expect(await sut.folderDisplayName == "Backups")
        #expect(await sut.configurationSummary == "Backups")
        #expect(await sut.isAvailable == false)

        await sut.clearConfiguration()

        #expect(await sut.isConfigured == false)
        #expect(await sut.folderDisplayName == nil)
    }

    @Test
    func iCloudDriveProvider_restoreRejectsInvalidData() async {
        let sut = iCloudDriveProvider()

        await #expect(throws: (any Error).self) {
            try await sut.restoreConfiguration(from: Data("invalid".utf8))
        }
    }

    @Test
    func iCloudDriveProvider_unconfiguredOperationsThrowProviderNotConfigured() async {
        let sut = iCloudDriveProvider()

        await expectProviderNotConfigured {
            try await sut.write(data: Data("payload".utf8), filename: "backup.pdf")
        }
        await expectProviderNotConfigured {
            _ = try await sut.listBackups()
        }
        await expectProviderNotConfigured {
            try await sut.delete(filename: "backup.pdf")
        }
    }

    /// A backup never replaces a file that's there, which could be another vault's backup.
    @Test
    func iCloudDriveProvider_write_neverReplacesAFile() async throws {
        try await withTemporaryDirectory { folder in
            let sut = try await Self.provider(backingUpTo: folder)
            try await sut.write(data: Data("first".utf8), filename: "vault-auto-backup-a.pdf")

            await #expect(throws: AutoBackupError.backupFileExists) {
                try await sut.write(data: Data("second".utf8), filename: "vault-auto-backup-a.pdf")
            }

            let file = folder.appending(path: "vault-auto-backup-a.pdf")
            #expect(try Data(contentsOf: file) == Data("first".utf8))
            #expect(try Self.fileNames(in: folder) == ["vault-auto-backup-a.pdf"])
            #expect(try await sut.containsBackup(filename: "vault-auto-backup-a.pdf"))
            #expect(try await !sut.containsBackup(filename: "vault-auto-backup-b.pdf"))
        }
    }

    #if os(macOS)
    /// The folder the user picked is kept as a bookmark, which a new provider, as after a relaunch, reads back to write
    /// into it. On the Mac it's security-scoped, as the sandbox needs. (iOS only configures with the document picker's
    /// security-scoped URLs, which a test can't make.)
    @Test
    func iCloudDriveProvider_configure_keepsTheFolderAcrossARelaunch() async throws {
        try await withTemporaryDirectory { folder in
            let picked = iCloudDriveProvider()
            try await picked.configure(with: folder)
            let configuration = try #require(await picked.configurationData)

            let relaunched = iCloudDriveProvider()
            try await relaunched.restoreConfiguration(from: configuration)
            try await relaunched.write(data: Data("backup".utf8), filename: "vault-auto-backup-a.pdf")

            #expect(await relaunched.isConfigured)
            #expect(await relaunched.folderDisplayName == folder.lastPathComponent)
            #expect(try Self.fileNames(in: folder) == ["vault-auto-backup-a.pdf"])
        }
    }

    @Test
    func iCloudDriveProvider_onTheMac_bookmarksAreSecurityScoped() {
        #expect(iCloudDriveProvider.bookmarkCreationOptions == .withSecurityScope)
        #expect(iCloudDriveProvider.bookmarkResolutionOptions == .withSecurityScope)
    }
    #endif

    /// A file only in iCloud for now has a hidden placeholder instead, which isn't listed, but is there: it's never
    /// replaced, and cleaning up doesn't forget it.
    @Test
    func iCloudDriveProvider_aFileOnlyInICloud_isThereButNotListed() async throws {
        try await withTemporaryDirectory { folder in
            let sut = try await Self.provider(backingUpTo: folder)
            try Data().write(to: folder.appending(path: ".vault-auto-backup-a.pdf.icloud"))

            await #expect(throws: AutoBackupError.backupFileExists) {
                try await sut.write(data: Data("new".utf8), filename: "vault-auto-backup-a.pdf")
            }

            #expect(try await sut.containsBackup(filename: "vault-auto-backup-a.pdf"))
            #expect(try await sut.listBackups().isEmpty)
            #expect(try Self.fileNames(in: folder) == [".vault-auto-backup-a.pdf.icloud"])
        }
    }

    @Test
    func autoBackupErrorsExposeDescriptionsAndRecoverySuggestions() {
        let cases: [AutoBackupError] = [
            .noProviderSelected,
            .providerNotConfigured,
            .providerUnavailable(reason: "Unavailable"),
            .accessDenied,
            .backupPasswordNotSet,
            .pdfGenerationFailed(reason: "PDF"),
            .writeFailed(reason: "Write"),
            .backupFileExists,
            .cleanupFailed(reason: "Cleanup"),
            .networkUnavailable,
            .storageFull,
            .unknown(reason: "Unknown"),
        ]

        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
        }
    }
}

extension AutoBackupProviderCoverageTests {
    /// A provider backing up to `folder`, as if the user had picked it.
    private static func provider(backingUpTo folder: URL) async throws -> iCloudDriveProvider {
        let sut = iCloudDriveProvider()
        let bookmark = try folder.bookmarkData(
            options: iCloudDriveProvider.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
        )
        let configuration = iCloudDriveProviderConfiguration(folderBookmark: bookmark, folderDisplayName: "Backups")
        try await sut.restoreConfiguration(from: JSONEncoder().encode(configuration))
        return sut
    }

    private static func fileNames(in folder: URL) throws -> Set<String> {
        try Set(FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))
    }
}

private func expectProviderNotConfigured(
    _ operation: () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation,
) async {
    do {
        try await operation()
        Issue.record("Expected providerNotConfigured", sourceLocation: sourceLocation)
    } catch let error as AutoBackupError {
        #expect(error == .providerNotConfigured, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Expected AutoBackupError, got \(error)", sourceLocation: sourceLocation)
    }
}
