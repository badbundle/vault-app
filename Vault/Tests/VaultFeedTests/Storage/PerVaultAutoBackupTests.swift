import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// Auto-backup across two encrypted vaults, put together as the app has it (`VaultRoot`): the store session, each
/// vault's settings through `OpenVaultBackupSettings`, and the data model and auto-backup reading them.
///
/// Unlike `AutoBackupServiceImplTests`, the session switches on its own here, and the settings only follow once the app
/// gets round to it, so these cover the moments in between.
@MainActor
@Suite(.rendersPDFBackups)
struct PerVaultAutoBackupTests {
    @Test
    func eachVault_backsUpIntoItsOwnSettings() async throws {
        let app = try await App()
        try await app.backUp()

        try await app.open(app.second)
        try await app.backUp()

        let first = try app.first.savedState().vault.settings
        let second = try app.second.savedState().vault.settings
        #expect(first.autoBackup.backupFilenames.count == 1)
        #expect(second.autoBackup.backupFilenames.count == 1)
        #expect(first.autoBackup.backupFilenames != second.autoBackup.backupFilenames)
        #expect(first.lastBackupEvent?.kind == .exportedToAutoBackup(providerID: "test"))
        #expect(second.lastBackupEvent?.kind == .exportedToAutoBackup(providerID: "test"))
        #expect(app.provider.files.count == 2)
    }

    /// The session has switched to the second vault, and nothing has followed it yet: auto-backup still has the first
    /// vault's destination and password. A backup started then would be of the second vault, so none is.
    @Test
    func backupStartedAfterTheSessionSwitchedButBeforeTheSettingsFollowed_writesNothing() async throws {
        let app = try await App()
        let secondStore = try await app.second.openStore()

        await app.session.switchTo(.unlocked(secondStore))
        await app.service.forceBackup()

        #expect(app.provider.writeCallCount == 0)
        #expect(try app.first.savedState().vault.settings == App.firstSettings)
        #expect(try app.second.savedState().vault.settings == App.secondSettings)

        await app.followTheOpenVault()
        #expect(app.service.configuration == App.secondSettings.autoBackup)
    }

    /// The session switches while a backup of the first vault is being written. The file is the first vault's, in its
    /// destination, but it's recorded, and logged, in neither vault.
    @Test
    func backupWrittenAsTheSessionSwitches_isRecordedInNeitherVault() async throws {
        let app = try await App()
        let secondStore = try await app.second.openStore()
        let session = app.session
        app.provider.writeHandler = { _, _ in
            await session.switchTo(.unlocked(secondStore))
        }

        await app.service.forceBackup()

        #expect(app.provider.writeCallCount == 1)
        #expect(app.logger.lastBackupEvent() == nil)
        #expect(try app.first.savedState().vault.settings == App.firstSettings)
        #expect(try app.second.savedState().vault.settings == App.secondSettings)

        app.provider.writeHandler = nil
        await app.followTheOpenVault()
        #expect(app.service.configuration == App.secondSettings.autoBackup)
        #expect(app.dataModel.lastBackupEvent == nil)
    }

    /// The app locks while a backup is being written, and the second vault is unlocked. Nothing of the first vault's
    /// backup reaches the second, or shows in it.
    @Test
    func backupUnderwayWhenTheAppLocksAndAnotherVaultOpens_showsNothingInIt() async throws {
        let app = try await App()
        let writeStarted = Pending<Void>.signal()
        let releaseWrite = Pending<Void>.signal()
        app.provider.writeHandler = { _, _ in
            await writeStarted.fulfill()
            try await releaseWrite.wait()
        }
        let backup = Task { await app.service.forceBackup() }
        try await writeStarted.wait()

        await app.session.lock()
        // Auto-backup waits for the backup underway before it sets up the next destination.
        let following = Task { await app.followTheOpenVault() }
        await releaseWrite.fulfill()
        await backup.value
        await following.value
        try await app.open(app.second)

        #expect(app.service.status == .completed(Date(timeIntervalSince1970: 4000)))
        #expect(app.service.configuration == App.secondSettings.autoBackup)
        #expect(app.dataModel.lastBackupEvent == nil)
        #expect(try app.second.savedState().vault.settings == App.secondSettings)
        #expect(app.provider.events.last == "restore second")
    }
}

// MARK: - App

extension PerVaultAutoBackupTests {
    /// Two vaults, each backing up to a folder of its own, with the first open and followed.
    @MainActor
    private struct App {
        static let firstSettings = settings(folder: "first", lastBackup: 3000)
        static let secondSettings = settings(folder: "second", lastBackup: 4000)

        let first: EncryptedVaultFixture
        let second: EncryptedVaultFixture
        let session: VaultStoreSession
        let settings: OpenVaultBackupSettings
        let logger: BackupEventLoggerImpl
        let dataModel: VaultDataModel
        let provider: BackupStorageProviderStub
        let service: AutoBackupServiceImpl
        let clock: EpochClockMock

        init() async throws {
            let clock = EpochClockMock(currentTime: 5000)
            let provider = BackupStorageProviderStub(id: "test")
            provider.clock = clock
            let first = try EncryptedVaultFixture(state: .empty(with: Self.firstSettings), slotIndex: 2)
            let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
            let settings = try OpenVaultBackupSettings.inMemory(session: session, clock: clock)
            let logger = BackupEventLoggerImpl(storage: settings, clock: clock)
            let dataModel = anyVaultDataModel(
                vaultStore: session,
                backupPasswordStore: settings,
                backupEventLogger: logger,
            )
            self.first = first
            second = try await first.addingVault(inSlot: 9, state: .empty(with: Self.secondSettings))
            self.session = session
            self.settings = settings
            self.logger = logger
            self.dataModel = dataModel
            self.provider = provider
            self.clock = clock
            service = AutoBackupServiceImpl(
                dataModel: dataModel,
                backupEventLogger: logger,
                clock: clock,
                configurationStorage: settings,
                providers: [provider],
                // Filling a fixed size is slow in tests, and these aren't about the padding.
                padding: .random,
            )
            await followTheOpenVault()
            await dataModel.loadBackupPassword()
        }

        /// Backing up to the stub provider's `folder`, with a backup password, having last backed up at
        /// `lastBackup`.
        private static func settings(folder: String, lastBackup: TimeInterval) -> VaultBackupSettings {
            var autoBackup = AutoBackupConfiguration.backingUp(providerConfig: folder)
            autoBackup.lastBackupDate = Date(timeIntervalSince1970: lastBackup)
            return VaultBackupSettings(
                backupPassword: StoredBackupPassword(password: anyBackupPassword(), lastSetDate: nil),
                autoBackup: autoBackup,
            )
        }

        /// What `VaultRoot` does each time the open vault changes.
        func followTheOpenVault() async {
            await settings.reload()
            await dataModel.openVaultDidChange()
            await service.vaultDidChange()
        }

        /// Unlocks `vault`, and follows it.
        func open(_ vault: EncryptedVaultFixture) async throws {
            try await session.switchTo(.unlocked(vault.openStore()))
            await followTheOpenVault()
            await dataModel.loadBackupPassword()
        }

        func backUp() async throws {
            clock.currentTime += 1
            await service.forceBackup()
            // Anything saved in the background has been once a later save finishes.
            try await settings.saveAutoBackupConfiguration(service.configuration, for: settings.vaultToken)
        }
    }
}
