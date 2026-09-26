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
        sut.exportedToPDF(backupDate: date, hash: .init(value: Data(hex: "1234")))

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

        sut.exportedToDevice(backupDate: date, hash: .init(value: Data(hex: "1234")))

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

        sut.exportedToAutoBackup(backupDate: date, hash: .init(value: Data(hex: "1234")), providerID: "icloud-drive")

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

        sut.exportedToPDF(backupDate: madeDate, hash: .init(value: Data(hex: "1234")))

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

        sut.exportedToPDF(backupDate: date, hash: .init(value: Data(hex: "1234")))

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
            sut.exportedToPDF(backupDate: date, hash: .init(value: Data(hex: "1234")))
        }
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
