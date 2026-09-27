import Combine
import Foundation
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

@MainActor
struct BackupEventLoggerImplTests {
    @Test
    func init_hasNoSideEffects() throws {
        let defaults = try testUserDefaults()
        let beforeKeys = defaults.keys
        _ = makeSUT(defaults: defaults)

        #expect(beforeKeys == defaults.keys)
    }

    @Test
    func lastBackupEvent_isNilIfNoBackup() throws {
        let defaults = try testUserDefaults()
        let sut = makeSUT(defaults: defaults)

        let backup = sut.lastBackupEvent()

        #expect(backup == nil)
    }

    @Test
    func lastBackup_getsStoredBackup() throws {
        let defaults = try testUserDefaults()
        let clock = EpochClockMock(currentTime: 100)
        let sut = makeSUT(defaults: defaults, clock: clock)
        let date = Date(timeIntervalSince1970: 1234)
        sut.exportedToPDF(backupDate: date, hash: .init(value: Data(hex: "1234")), vaultToken: sut.vaultToken)

        let backup = sut.lastBackupEvent()

        #expect(backup?.backupDate == date)
        #expect(backup?.eventDate == clock.currentDate)
        #expect(backup?.payloadHash == .init(value: Data(hex: "1234")))
        #expect(backup?.kind == .exportedToPDF)
    }

    @Test
    func exportedToDevice_savesDeviceEvent() throws {
        let defaults = try testUserDefaults()
        let clock = EpochClockMock(currentTime: 100)
        let sut = makeSUT(defaults: defaults, clock: clock)
        let date = Date(timeIntervalSince1970: 1234)

        sut.exportedToDevice(backupDate: date, hash: .init(value: Data(hex: "1234")), vaultToken: sut.vaultToken)

        let backup = sut.lastBackupEvent()
        #expect(backup?.backupDate == date)
        #expect(backup?.eventDate == clock.currentDate)
        #expect(backup?.payloadHash == .init(value: Data(hex: "1234")))
        #expect(backup?.kind == .exportedToDevice)
    }

    @Test
    func exportedToAutoBackup_savesAutoBackupEvent() throws {
        let defaults = try testUserDefaults()
        let clock = EpochClockMock(currentTime: 100)
        let sut = makeSUT(defaults: defaults, clock: clock)
        let date = Date(timeIntervalSince1970: 1234)

        sut.exportedToAutoBackup(
            backupDate: date,
            hash: .init(value: Data(hex: "1234")),
            providerID: "icloud-drive",
            vaultToken: sut.vaultToken,
        )

        let backup = sut.lastBackupEvent()
        #expect(backup?.backupDate == date)
        #expect(backup?.eventDate == clock.currentDate)
        #expect(backup?.payloadHash == .init(value: Data(hex: "1234")))
        #expect(backup?.kind == .exportedToAutoBackup(providerID: "icloud-drive"))
    }

    /// The backup is dated when the vault was exported into it, which is what its age goes by, and the event
    /// when it was logged: for a PDF, when it was saved, which can be a while after it was made.
    @Test
    func exportedToPDF_datesBackupWhenMadeAndEventWhenSaved() throws {
        let day: TimeInterval = 86400
        let madeDate = Date(timeIntervalSince1970: 0)
        let savedDate = madeDate.addingTimeInterval(3 * day)
        let defaults = try testUserDefaults()
        let sut = makeSUT(defaults: defaults, clock: EpochClockMock(currentTime: savedDate.timeIntervalSince1970))

        sut.exportedToPDF(backupDate: madeDate, hash: .init(value: Data(hex: "1234")), vaultToken: sut.vaultToken)

        let backup = try #require(sut.lastBackupEvent())
        #expect(backup.backupDate == madeDate)
        #expect(backup.eventDate == savedDate)
        // Eight days after it was made, though only five after it was saved.
        #expect(backup.staleness(at: madeDate.addingTimeInterval(8 * day)) == .stale)
    }

    @Test
    func exportedToPDF_savesToDefaults() throws {
        let defaults = try testUserDefaults()
        let beforeKeys = defaults.keys
        let sut = makeSUT(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1234)

        sut.exportedToPDF(backupDate: date, hash: .init(value: Data(hex: "1234")), vaultToken: sut.vaultToken)

        #expect(beforeKeys.symmetricDifference(defaults.keys) == ["vault.backup.last-event"])
    }

    @Test
    func loggedEventPublisher_logsOnSuccess() async throws {
        let defaults = try testUserDefaults()
        let sut = makeSUT(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1234)

        await confirmation { @MainActor confirmation in
            var bag = Set<AnyCancellable>()
            sut.loggedEventPublisher.sink { _ in
                confirmation.confirm()
            }.store(in: &bag)
            sut.exportedToPDF(backupDate: date, hash: .init(value: Data(hex: "1234")), vaultToken: sut.vaultToken)
        }
    }
}

// MARK: - Each vault's own

extension BackupEventLoggerImplTests {
    /// A backup of one vault that finishes once another is open isn't logged in either.
    @Test
    func exportedToPDF_forAVaultThatIsNotOpenAnyMore_logsNothing() async throws {
        let (first, second) = try await EncryptedVaultFixture.twoVaults()
        let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
        let settings = try OpenVaultBackupSettings.inMemory(session: session)
        await settings.reload()
        let sut = BackupEventLoggerImpl(storage: settings, clock: EpochClockMock(currentTime: 100))
        let token = sut.vaultToken
        var logged = [VaultBackupEvent]()
        let cancellable = sut.loggedEventPublisher.sink { logged.append($0) }

        try await session.switchTo(.unlocked(second.openStore()))
        await settings.reload()
        sut.exportedToPDF(backupDate: Date(), hash: .init(value: Data(hex: "1234")), vaultToken: token)

        #expect(sut.lastBackupEvent() == nil)
        #expect(logged.isEmpty)
        // Anything saved has been by the time a later save finishes.
        try await settings.saveAutoBackupConfiguration(AutoBackupConfiguration(), for: settings.vaultToken)
        #expect(try first.savedState().vault.settings.lastBackupEvent == nil)
        #expect(try second.savedState().vault.settings.lastBackupEvent == nil)
        cancellable.cancel()
    }

    @Test
    func exportedToPDF_forTheVaultThatIsOpen_logsItThere() async throws {
        let (first, second) = try await EncryptedVaultFixture.twoVaults()
        let session = try await VaultStoreSession(target: .unlocked(first.openStore()))
        let settings = try OpenVaultBackupSettings.inMemory(session: session)
        await settings.reload()
        let sut = BackupEventLoggerImpl(storage: settings, clock: EpochClockMock(currentTime: 100))

        sut.exportedToPDF(backupDate: Date(), hash: .init(value: Data(hex: "1234")), vaultToken: sut.vaultToken)

        #expect(sut.lastBackupEvent()?.kind == .exportedToPDF)
        try await settings.saveAutoBackupConfiguration(AutoBackupConfiguration(), for: settings.vaultToken)
        #expect(try first.savedState().vault.settings.lastBackupEvent?.kind == .exportedToPDF)
        #expect(try second.savedState().vault.settings.lastBackupEvent == nil)
    }
}

// MARK: - Helpers

extension BackupEventLoggerImplTests {
    private func makeSUT(
        defaults: UserDefaults,
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
    ) -> BackupEventLoggerImpl {
        BackupEventLoggerImpl(defaults: .init(userDefaults: defaults), clock: clock)
    }
}
