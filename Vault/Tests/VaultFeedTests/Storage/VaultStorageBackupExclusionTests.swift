import Foundation
import Testing
@testable import VaultFeed

/// Keep Out of Time Machine, on the Mac: the vault's storage directory's own `isExcludedFromBackup`, on unless the
/// user turns it off, which is kept with the app lock's device settings.
@MainActor
struct VaultStorageBackupExclusionTests {
    /// Keeping the vault out of backups is the protective choice, so it's what a launch does until the user chooses
    /// otherwise (C7), for a vault from before the setting too.
    @Test
    func apply_byDefault_keepsTheDirectoryOutOfBackups() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try VaultStorageBackupExclusion(directory: directory, settings: .keepingDeviceSettings())
            #expect(!sut.isExcluded)

            sut.apply()

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(sut.isExcluded)
            #expect(directoryIsExcluded)
        }
    }

    @Test
    func setExcluded_off_letsTheDirectoryIntoBackupsAndStoresTheChoice() async throws {
        try await withTemporaryDirectory { directory in
            let storage = InMemoryAppLockDeviceSettingsStorage()
            let sut = try VaultStorageBackupExclusion(
                directory: directory,
                settings: .keepingDeviceSettings(in: storage),
            )
            sut.apply()

            try sut.setExcluded(false)

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(!sut.isExcluded)
            #expect(!directoryIsExcluded)
            #expect(storage.settings?.includesVaultInBackups == true)
        }
    }

    /// Turning it off is remembered, so the next launch doesn't keep the vault out again.
    @Test
    func optOut_survivesARelaunch() async throws {
        try await withTemporaryDirectory { directory in
            let storage = InMemoryAppLockDeviceSettingsStorage()
            let first = try VaultStorageBackupExclusion(
                directory: directory,
                settings: .keepingDeviceSettings(in: storage),
            )
            first.apply()
            try first.setExcluded(false)

            let relaunched = try VaultStorageBackupExclusion(
                directory: directory,
                settings: .keepingDeviceSettings(in: storage),
            )
            relaunched.apply()

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(!relaunched.isExcluded)
            #expect(!directoryIsExcluded)
        }
    }

    /// Turning it back on is remembered too.
    @Test
    func setExcluded_on_afterAnOptOut_keepsTheDirectoryOutAgainAcrossARelaunch() async throws {
        try await withTemporaryDirectory { directory in
            let storage = InMemoryAppLockDeviceSettingsStorage()
            let sut = try VaultStorageBackupExclusion(
                directory: directory,
                settings: .keepingDeviceSettings(in: storage),
            )
            try sut.setExcluded(false)

            try sut.setExcluded(true)
            let relaunched = try VaultStorageBackupExclusion(
                directory: directory,
                settings: .keepingDeviceSettings(in: storage),
            )
            relaunched.apply()

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(relaunched.isExcluded)
            #expect(directoryIsExcluded)
            #expect(storage.settings?.includesVaultInBackups == false)
        }
    }

    /// If the choice can't be read, the vault is kept out, even after the user let it in.
    @Test
    func apply_choiceUnreadable_keepsTheDirectoryOutOfBackups() async throws {
        try await withTemporaryDirectory { directory in
            let storage = InMemoryAppLockDeviceSettingsStorage(
                settings: AppLockDeviceSettings(
                    erasesAfterFailedPasswords: false,
                    delaySeconds: 0,
                    includesVaultInBackups: true,
                ),
            )
            storage.failToLoad()
            let sut = try VaultStorageBackupExclusion(
                directory: directory,
                settings: .keepingDeviceSettings(in: storage),
            )

            sut.apply()

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(sut.isExcluded)
            #expect(directoryIsExcluded)
        }
    }

    /// If the choice can't be stored, nothing changes, so the vault isn't let in without the next launch knowing.
    @Test
    func setExcluded_off_choiceCantBeStored_throwsAndKeepsTheDirectoryOut() async throws {
        try await withTemporaryDirectory { directory in
            let storage = InMemoryAppLockDeviceSettingsStorage()
            let sut = try VaultStorageBackupExclusion(
                directory: directory,
                settings: .keepingDeviceSettings(in: storage),
            )
            sut.apply()
            storage.failToStore()

            #expect(throws: InMemoryAppLockDeviceSettingsStorage.Failure.self) {
                try sut.setExcluded(false)
            }

            let directoryIsExcluded = try Self.directoryIsExcluded(directory)
            #expect(sut.isExcluded)
            #expect(directoryIsExcluded)
            #expect(storage.settings?.includesVaultInBackups == false)
        }
    }

    /// The choice is stored even if the directory can't be changed, so the next launch applies it.
    @Test
    func setExcluded_directoryCantBeChanged_throwsButKeepsTheChoice() throws {
        let missing = URL.temporaryDirectory.appending(
            path: "missing-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        let storage = InMemoryAppLockDeviceSettingsStorage(
            settings: AppLockDeviceSettings(
                erasesAfterFailedPasswords: false,
                delaySeconds: 0,
                includesVaultInBackups: true,
            ),
        )
        let sut = try VaultStorageBackupExclusion(directory: missing, settings: .keepingDeviceSettings(in: storage))

        #expect(throws: (any Error).self) {
            try sut.setExcluded(true)
        }

        #expect(!sut.isExcluded)
        #expect(storage.settings?.includesVaultInBackups == false)
    }

    /// Settings stored before the choice existed read it as the vault kept out.
    @Test
    func deviceSettings_storedWithoutTheChoice_keepTheVaultOut() throws {
        let stored = Data(#"{"erasesAfterFailedPasswords":true,"delaySeconds":300}"#.utf8)

        let settings = try JSONDecoder().decode(AppLockDeviceSettings.self, from: stored)

        #expect(settings == AppLockDeviceSettings(erasesAfterFailedPasswords: true, delaySeconds: 300))
        #expect(!settings.includesVaultInBackups)
    }

    private static func directoryIsExcluded(_ directory: URL) throws -> Bool {
        var url = directory
        url.removeAllCachedResourceValues()
        return try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }
}
