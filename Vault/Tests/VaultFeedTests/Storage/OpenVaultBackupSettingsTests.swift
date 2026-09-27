import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// The backup settings of whichever vault is open: the plain store's device-wide ones, an encrypted vault's own, or
/// none while locked.
@MainActor
struct OpenVaultBackupSettingsTests {
    private let clock = EpochClockMock(currentTime: 5000)
}

// MARK: - Plain store

extension OpenVaultBackupSettingsTests {
    @Test
    func plain_readsAndWritesTheDeviceSettings() async throws {
        let device = try TestDeviceBackupSettings()
        let sut = try makeSUT(session: VaultStoreSession(target: .plain(GatedVaultStore())), device: device)
        await sut.reload()
        let settings = anyVaultBackupSettings()

        try await sut.set(password: #require(settings.backupPassword).password)
        try sut.saveLastBackupEvent(#require(settings.lastBackupEvent), for: sut.vaultToken)
        try sut.savePDFUserHint("My hint", for: sut.vaultToken)
        try await sut.saveAutoBackupConfiguration(settings.autoBackup, for: sut.vaultToken)

        #expect(try await device.passwordStore.fetchPassword() == settings.backupPassword?.password)
        #expect(device.defaults.lastBackupEvent() == settings.lastBackupEvent)
        #expect(device.defaults.autoBackupConfiguration() == settings.autoBackup)
        #expect(device.defaults.pdfUserHint() == "My hint")
        #expect(try await sut.fetchPassword() == settings.backupPassword?.password)
        #expect(try await sut.fetchPasswordMetadata() == BackupPasswordMetadata(lastSetDate: clock.currentDate))
        #expect(sut.lastBackupEvent() == settings.lastBackupEvent)
        #expect(sut.autoBackupConfiguration() == settings.autoBackup)
        #expect(sut.pdfUserHint() == "My hint")
        #expect(sut.isDeviceWide)
        // The keychain asks for itself.
        #expect(device.authentications.value == 0)
    }

    @Test
    func plain_readsWhatTheDeviceHasSaved() async throws {
        let device = try TestDeviceBackupSettings()
        let settings = anyVaultBackupSettings()
        try device.device.save(VaultBackupSettings(
            lastBackupEvent: settings.lastBackupEvent,
            autoBackup: settings.autoBackup,
            pdfUserHint: "Saved hint",
        ))
        let sut = try makeSUT(session: VaultStoreSession(target: .plain(GatedVaultStore())), device: device)

        await sut.reload()

        #expect(sut.lastBackupEvent() == settings.lastBackupEvent)
        #expect(sut.autoBackupConfiguration() == settings.autoBackup)
        #expect(sut.pdfUserHint() == "Saved hint")
    }

    /// An erase, or a conversion, locks the session, then deletes the plain store's settings. A change meant for the
    /// plain store as it was open before is dropped, so it can't put them back, even once the session has switched
    /// back to the same store.
    @Test
    func plain_afterTheSessionLocked_savesNothingOnTheDevice() async throws {
        let store = GatedVaultStore()
        let session = VaultStoreSession(target: .plain(store))
        let device = try TestDeviceBackupSettings()
        let sut = try makeSUT(session: session, device: device)
        await sut.reload()
        let token = sut.vaultToken

        await session.lock()
        try await device.device.delete()
        await session.switchTo(.plain(store))

        await #expect(throws: VaultStoreSessionError.locked) { try await sut.set(password: anyBackupPassword()) }
        try sut.saveLastBackupEvent(#require(anyVaultBackupSettings().lastBackupEvent), for: token)
        try sut.savePDFUserHint("Late hint", for: token)
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.saveAutoBackupConfiguration(.written(["late.pdf"]), for: token)
        }
        #expect(try await device.device.readBackupPassword() == nil)
        #expect(device.device.read(backupPassword: nil) == VaultBackupSettings())
        #expect(await !sut.isOpen(token))
    }
}

// MARK: - An encrypted vault

extension OpenVaultBackupSettingsTests {
    @Test
    func unlocked_readsTheVaultsOwnSettings() async throws {
        var settings = anyVaultBackupSettings()
        settings.pdfUserHint = "The vault's hint"
        let fixture = try EncryptedVaultFixture(state: .empty(with: settings))
        let device = try TestDeviceBackupSettings()
        let sut = try await makeSUT(session: VaultStoreSession(target: .unlocked(fixture.openStore())), device: device)

        await sut.reload()

        #expect(try await sut.fetchPassword() == settings.backupPassword?.password)
        #expect(device.authentications.value == 1)
        let lastSetDate = settings.backupPassword?.lastSetDate
        #expect(try await sut.fetchPasswordMetadata() == BackupPasswordMetadata(lastSetDate: lastSetDate))
        #expect(sut.lastBackupEvent() == settings.lastBackupEvent)
        #expect(sut.autoBackupConfiguration() == settings.autoBackup)
        #expect(sut.pdfUserHint() == "The vault's hint")
        #expect(!sut.isDeviceWide)
    }

    @Test
    func unlocked_savesChangesInTheVaultsSlotAndNotOnTheDevice() async throws {
        let fixture = try EncryptedVaultFixture()
        let device = try TestDeviceBackupSettings()
        let sut = try await makeSUT(session: VaultStoreSession(target: .unlocked(fixture.openStore())), device: device)
        await sut.reload()
        let settings = anyVaultBackupSettings()
        let password = try #require(settings.backupPassword).password

        try await sut.set(password: password)
        try sut.saveLastBackupEvent(#require(settings.lastBackupEvent), for: sut.vaultToken)
        try sut.savePDFUserHint("The vault's hint", for: sut.vaultToken)
        try await sut.saveAutoBackupConfiguration(settings.autoBackup, for: sut.vaultToken)

        let saved = try fixture.savedState().vault.settings
        #expect(saved.backupPassword == StoredBackupPassword(password: password, lastSetDate: clock.currentDate))
        #expect(saved.lastBackupEvent == settings.lastBackupEvent)
        #expect(saved.autoBackup == settings.autoBackup)
        #expect(saved.pdfUserHint == "The vault's hint")
        #expect(try await sut.fetchPassword() == password)
        #expect(try await device.passwordStore.fetchPasswordMetadata() == nil)
        #expect(device.device.read(backupPassword: nil) == VaultBackupSettings())
    }

    /// As the keychain asks for the plain store's.
    @Test
    func unlocked_fetchPassword_whenTheUserDoesNotAuthenticate_throws() async throws {
        let fixture = try EncryptedVaultFixture(state: .empty(with: anyVaultBackupSettings()))
        let device = try TestDeviceBackupSettings(authenticationError: TestError())
        let sut = try await makeSUT(session: VaultStoreSession(target: .unlocked(fixture.openStore())), device: device)
        await sut.reload()

        await #expect(throws: TestError.self) { try await sut.fetchPassword() }
    }

    @Test
    func unlocked_fetchPassword_withNoneSet_isNilWithoutAskingTheUser() async throws {
        let fixture = try EncryptedVaultFixture()
        let device = try TestDeviceBackupSettings()
        let sut = try await makeSUT(session: VaultStoreSession(target: .unlocked(fixture.openStore())), device: device)
        await sut.reload()

        #expect(try await sut.fetchPassword() == nil)
        #expect(try await sut.fetchPasswordMetadata() == nil)
        #expect(device.authentications.value == 0)
    }

    /// The event is saved in the background: the next change to save waits for it.
    @Test
    func unlocked_backupEventLogger_logsIntoTheVault() async throws {
        let fixture = try EncryptedVaultFixture()
        let sut = try await makeSUT(session: VaultStoreSession(target: .unlocked(fixture.openStore())))
        await sut.reload()
        let logger = BackupEventLoggerImpl(storage: sut, clock: clock)
        let hash = Digest<VaultApplicationPayload>.SHA256(value: Data(repeating: 1, count: 32))

        logger.exportedToPDF(backupDate: Date(timeIntervalSince1970: 10), hash: hash, vaultToken: logger.vaultToken)
        try await sut.saveAutoBackupConfiguration(AutoBackupConfiguration(), for: sut.vaultToken)

        let event = try #require(try fixture.savedState().vault.settings.lastBackupEvent)
        #expect(event.kind == .exportedToPDF)
        #expect(event.payloadHash == hash)
        #expect(logger.lastBackupEvent() == event)
    }
}

// MARK: - Locked

extension OpenVaultBackupSettingsTests {
    @Test
    func locked_hasNoSettings() async throws {
        let device = try TestDeviceBackupSettings()
        try await device.passwordStore.set(password: anyBackupPassword())
        let sut = try makeSUT(session: VaultStoreSession(target: .locked), device: device)
        await sut.reload()

        await #expect(throws: VaultStoreSessionError.locked) { try await sut.fetchPassword() }
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.fetchPasswordMetadata() }
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.set(password: anyBackupPassword()) }
        let event = try #require(anyVaultBackupSettings().lastBackupEvent)
        #expect(throws: VaultStoreSessionError.locked) { try sut.saveLastBackupEvent(event, for: sut.vaultToken) }
        #expect(throws: VaultStoreSessionError.locked) { try sut.savePDFUserHint("Hint", for: sut.vaultToken) }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.saveAutoBackupConfiguration(AutoBackupConfiguration(), for: sut.vaultToken)
        }
        #expect(sut.lastBackupEvent() == nil)
        #expect(sut.autoBackupConfiguration() == nil)
        #expect(sut.pdfUserHint() == nil)
        #expect(!sut.isDeviceWide)
        #expect(await !sut.isOpen(sut.vaultToken))
    }

    /// It has nothing until it's read what's open.
    @Test
    func init_hasNoSettingsUntilReloaded() async throws {
        let fixture = try EncryptedVaultFixture(state: .empty(with: anyVaultBackupSettings()))
        let sut = try await makeSUT(session: VaultStoreSession(target: .unlocked(fixture.openStore())))

        #expect(sut.autoBackupConfiguration() == nil)
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.fetchPassword() }
    }
}

// MARK: - Switching vault

extension OpenVaultBackupSettingsTests {
    @Test
    func reload_afterAnotherVaultOpened_readsItsSettings() async throws {
        let (first, second) = try await EncryptedVaultFixture.twoVaults()
        let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
        let sut = try makeSUT(session: session)
        await sut.reload()

        try await session.switchTo(.unlocked(second.openStore()))
        await sut.reload()

        #expect(sut.autoBackupConfiguration() == .written(["second.pdf"]))
        #expect(try await sut.fetchPassword() == nil)
    }

    @Test
    func reload_afterSwitchingToThePlainStore_readsTheDeviceSettings() async throws {
        let (first, _) = try await EncryptedVaultFixture.twoVaults()
        let device = try TestDeviceBackupSettings()
        try await device.defaults.saveAutoBackupConfiguration(.written(["device.pdf"]), for: 0)
        let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
        let sut = try makeSUT(session: session, device: device)
        await sut.reload()

        await session.switchTo(.plain(GatedVaultStore()))
        await sut.reload()

        #expect(sut.autoBackupConfiguration() == .written(["device.pdf"]))
    }

    /// A vault's token stops being open the moment the session switches, before anything has reloaded.
    @Test
    func isOpen_isFalseOnceTheSessionSwitches() async throws {
        let (first, second) = try await EncryptedVaultFixture.twoVaults()
        let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
        let sut = try makeSUT(session: session)
        await sut.reload()
        let token = sut.vaultToken
        #expect(await sut.isOpen(token))

        try await session.switchTo(.unlocked(second.openStore()))

        #expect(await !sut.isOpen(token))
        await sut.reload()
        #expect(await !sut.isOpen(token))
        #expect(await sut.isOpen(sut.vaultToken))
    }

    @Test
    func isOpen_isFalseOnceTheSessionLocks() async throws {
        let (first, _) = try await EncryptedVaultFixture.twoVaults()
        let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
        let sut = try makeSUT(session: session)
        await sut.reload()

        await session.lock()

        #expect(await !sut.isOpen(sut.vaultToken))
    }

    /// A configuration read from one vault is never saved into another.
    @Test
    func saveAutoBackupConfiguration_withATokenFromAnEarlierVault_isRefused() async throws {
        let (first, second) = try await EncryptedVaultFixture.twoVaults()
        let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
        let sut = try makeSUT(session: session)
        await sut.reload()
        let token = sut.vaultToken

        try await session.switchTo(.unlocked(second.openStore()))
        await sut.reload()

        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.saveAutoBackupConfiguration(.written(["mixed up.pdf"]), for: token)
        }
        #expect(throws: VaultStoreSessionError.locked) { try sut.savePDFUserHint("Mixed up", for: token) }
        #expect(try first.savedState().vault.settings.autoBackup == .written(["first.pdf"]))
        #expect(try second.savedState().vault.settings.autoBackup == .written(["second.pdf"]))
        #expect(try second.savedState().vault.settings.pdfUserHint == nil)
    }

    /// The session has switched, and this hasn't reloaded yet: a change meant for the vault that was open is
    /// dropped, rather than saved into either.
    @Test
    func set_afterTheSessionSwitchedButBeforeReloading_savesNothing() async throws {
        let (first, second) = try await EncryptedVaultFixture.twoVaults()
        let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
        let sut = try makeSUT(session: session)
        await sut.reload()

        try await session.switchTo(.unlocked(second.openStore()))

        await #expect(throws: VaultStoreSessionError.locked) { try await sut.set(password: anyBackupPassword()) }
        try sut.saveLastBackupEvent(#require(anyVaultBackupSettings().lastBackupEvent), for: sut.vaultToken)
        try sut.savePDFUserHint("Mixed up", for: sut.vaultToken)
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.saveAutoBackupConfiguration(.written(["mixed up.pdf"]), for: sut.vaultToken)
        }
        for vault in [first, second] {
            let saved = try vault.savedState().vault.settings
            #expect(saved.backupPassword == nil)
            #expect(saved.lastBackupEvent == nil)
            #expect(saved.pdfUserHint == nil)
            #expect(!saved.autoBackup.backupFilenames.contains("mixed up.pdf"))
        }
    }
}

// MARK: - Helpers

extension OpenVaultBackupSettingsTests {
    private func makeSUT(
        session: VaultStoreSession,
        device: TestDeviceBackupSettings? = nil,
    ) throws -> OpenVaultBackupSettings {
        try .inMemory(session: session, device: device, clock: clock)
    }
}
