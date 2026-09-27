import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// The plain store's backup settings, which turning encryption on moves into the real vault.
@MainActor
struct DeviceBackupSettingsTests {
    private let secureStorage = InMemorySecureStorage(canReadAttributesWithoutAuthentication: true)
    private let clock = EpochClockMock(currentTime: 1000)
}

extension DeviceBackupSettingsTests {
    @Test
    func read_readsTheKeychainAndUserDefaults() async throws {
        let defaults = try Defaults(userDefaults: testUserDefaults())
        let passwordStore = BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock)
        // Its password was set at 1000, which is when the clock says it is.
        let settings = anyVaultBackupSettings()
        try await passwordStore.set(password: #require(settings.backupPassword).password)
        try defaults.saveLastBackupEvent(#require(settings.lastBackupEvent), for: defaults.vaultToken)
        try await defaults.saveAutoBackupConfiguration(settings.autoBackup, for: defaults.vaultToken)
        try defaults.savePDFUserHint(#require(settings.pdfUserHint), for: defaults.vaultToken)
        let sut = DeviceBackupSettings(passwordStore: passwordStore, secureStorage: secureStorage, defaults: defaults)

        let password = try await sut.readBackupPassword()

        #expect(password == settings.backupPassword)
        #expect(sut.read(backupPassword: password) == settings)
    }

    @Test
    func read_withNoneSet_isTheDefaults() async throws {
        let sut = try makeSUT()

        #expect(try await sut.readBackupPassword() == nil)
        #expect(sut.read(backupPassword: nil) == VaultBackupSettings())
    }

    /// Reading the backup password asks the user to authenticate: if they don't, the settings can't be moved.
    @Test
    func readBackupPassword_whenTheUserDoesNotAuthenticate_throws() async throws {
        let passwordStore = BackupPasswordStoreMock()
        passwordStore.fetchPasswordHandler = { throw TestError() }
        let sut = try DeviceBackupSettings(
            passwordStore: passwordStore,
            secureStorage: secureStorage,
            defaults: Defaults(userDefaults: testUserDefaults()),
        )

        await #expect(throws: TestError.self) { try await sut.readBackupPassword() }
    }

    @Test
    func save_thenRead_keepsEverySettingButThePassword() throws {
        let sut = try makeSUT()
        var settings = anyVaultBackupSettings()

        try sut.save(settings)

        settings.backupPassword = nil
        #expect(sut.read(backupPassword: nil) == settings)
    }

    @Test
    func save_withSettingsUnset_clearsThem() throws {
        let sut = try makeSUT()
        let settings = anyVaultBackupSettings()
        try sut.save(settings)

        try sut.save(VaultBackupSettings())

        #expect(sut.read(backupPassword: nil) == VaultBackupSettings())
    }

    @Test
    func delete_leavesNoneOnTheDevice() async throws {
        let defaults = try Defaults(userDefaults: testUserDefaults())
        let passwordStore = BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock)
        let settings = anyVaultBackupSettings()
        try await passwordStore.set(password: #require(settings.backupPassword).password)
        let sut = DeviceBackupSettings(passwordStore: passwordStore, secureStorage: secureStorage, defaults: defaults)
        try sut.save(settings)

        try await sut.delete()

        #expect(await !secureStorage.contains(key: VaultIdentifiers.SecureStorageKey.backupPassword.rawValue))
        #expect(await !secureStorage.contains(key: VaultIdentifiers.SecureStorageKey.backupPasswordMetadata.rawValue))
        #expect(defaults.lastBackupEvent() == nil)
        #expect(defaults.autoBackupConfiguration() == nil)
        #expect(defaults.pdfUserHint() == nil)
        #expect(try await sut.readBackupPassword() == nil)
        #expect(sut.read(backupPassword: nil) == VaultBackupSettings())
    }

    @Test
    func delete_withNoneSet_succeeds() async throws {
        let sut = try makeSUT()

        try await sut.delete()

        #expect(sut.read(backupPassword: nil) == VaultBackupSettings())
    }
}

// MARK: - Helpers

extension DeviceBackupSettingsTests {
    private func makeSUT() throws -> DeviceBackupSettings {
        try DeviceBackupSettings(
            passwordStore: BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock),
            secureStorage: secureStorage,
            defaults: Defaults(userDefaults: testUserDefaults()),
        )
    }
}
