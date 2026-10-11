import Foundation
import Testing
@testable import VaultFeed

/// Keep Out of Time Machine, on the Mac: the vault's storage directory's own `isExcludedFromBackup`.
@MainActor
struct VaultStorageBackupExclusionTests {
    /// A backup is how a lost Mac's vault comes back, so the vault is in them until the user chooses otherwise.
    @Test
    func isExcluded_isOffByDefault() async throws {
        try await withTemporaryDirectory { directory in
            let sut = VaultStorageBackupExclusion(directory: directory)

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(!sut.isExcluded)
            #expect(!directoryIsExcluded)
        }
    }

    @Test
    func setExcluded_keepsTheDirectoryOutOfBackups() async throws {
        try await withTemporaryDirectory { directory in
            let sut = VaultStorageBackupExclusion(directory: directory)

            try sut.setExcluded(true)

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(sut.isExcluded)
            #expect(directoryIsExcluded)
            // The directory is the only record of it, so the next launch finds it as it was left.
            #expect(VaultStorageBackupExclusion(directory: directory).isExcluded)
        }
    }

    @Test
    func setExcluded_off_letsTheDirectoryBackIntoBackups() async throws {
        try await withTemporaryDirectory { directory in
            let sut = VaultStorageBackupExclusion(directory: directory)
            try sut.setExcluded(true)

            try sut.setExcluded(false)

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(!sut.isExcluded)
            #expect(!directoryIsExcluded)
            #expect(!VaultStorageBackupExclusion(directory: directory).isExcluded)
        }
    }

    /// If the directory can't be changed, it says what the directory still has.
    @Test
    func setExcluded_directoryMissing_throwsAndStaysOff() throws {
        let missing = URL.temporaryDirectory.appending(
            path: "missing-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let sut = VaultStorageBackupExclusion(directory: missing)

        #expect(throws: (any Error).self) {
            try sut.setExcluded(true)
        }

        #expect(!sut.isExcluded)
    }

    private static func directoryIsExcluded(_ directory: URL) throws -> Bool {
        var url = directory
        url.removeAllCachedResourceValues()
        return try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }
}
