import Foundation
import Testing
@testable import VaultFeed

/// How a vault's own backup settings are kept in its payload.
struct VaultBackupSettingsTests {
    @Test
    func coding_roundTripsEverySetting() throws {
        let settings = anyVaultBackupSettings(backupFilenames: ["first.pdf", "second.pdf"])

        let decoded = try JSONDecoder().decode(VaultBackupSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded == settings)
    }

    @Test
    func coding_roundTripsThePasswordWithoutTheDateItWasSet() throws {
        var settings = anyVaultBackupSettings()
        settings.backupPassword?.lastSetDate = nil

        let decoded = try JSONDecoder().decode(VaultBackupSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded == settings)
    }

    /// Every key is written whatever it holds, `nil` as `null`, so a vault with no settings has a section of the same
    /// shape as one with every setting.
    @Test
    func encode_writesEveryKeyWhetherOrNotItIsSet() throws {
        let none = try Self.json(VaultBackupSettings())
        let every = try Self.json(anyVaultBackupSettings())

        #expect(Set(none.keys) == ["backupPassword", "lastBackupEvent", "autoBackup", "pdfUserHint"])
        #expect(Set(none.keys) == Set(every.keys))
        #expect(none["backupPassword"] is NSNull)
        #expect(none["lastBackupEvent"] is NSNull)
        #expect(none["pdfUserHint"] is NSNull)
        let noAutoBackup = try #require(none["autoBackup"] as? [String: Any])
        let everyAutoBackup = try #require(every["autoBackup"] as? [String: Any])
        #expect(Set(noAutoBackup.keys) == Set(everyAutoBackup.keys))
        #expect(noAutoBackup["providerID"] is NSNull)
        #expect(noAutoBackup["lastBackupHash"] is NSNull)
        #expect(noAutoBackup["lastBackupDate"] is NSNull)
        #expect(noAutoBackup["backupFilenames"] as? [String] == [])
    }

    @Test
    func encode_writesThePasswordsDerivedKeyNotThePassword() throws {
        let every = try Self.json(anyVaultBackupSettings())

        let password = try #require(every["backupPassword"] as? [String: Any])

        #expect(Set(password.keys) == ["key", "salt", "keyDeriver", "lastSetDate"])
    }

    /// Settings added later read as their defaults when they're missing.
    @Test
    func decode_readsMissingSettingsAsTheirDefaults() throws {
        let decoded = try JSONDecoder().decode(VaultBackupSettings.self, from: Data("{}".utf8))

        #expect(decoded == VaultBackupSettings())
    }

    /// A configuration saved before auto-backup recorded its files reads as having written none, so cleaning up
    /// deletes nothing it finds.
    @Test
    func decode_readsAnAutoBackupConfigurationSavedBeforeItRecordedItsFiles() throws {
        let json = #"{"isEnabled":true,"retentionDays":7,"providerID":"icloud","providerConfigs":{}}"#

        let decoded = try JSONDecoder().decode(AutoBackupConfiguration.self, from: Data(json.utf8))

        #expect(decoded.isEnabled)
        #expect(decoded.retentionDays == .days7)
        #expect(decoded.providerID == "icloud")
        #expect(decoded.backupFilenames.isEmpty)
    }
}

// MARK: - Helpers

extension VaultBackupSettingsTests {
    private static func json(_ settings: VaultBackupSettings) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
        return try #require(object as? [String: Any])
    }
}
