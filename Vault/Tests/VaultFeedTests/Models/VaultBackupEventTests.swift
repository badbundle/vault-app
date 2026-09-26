import CryptoEngine
import Foundation
import Testing
import VaultFeed

struct VaultBackupEventTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test(arguments: [0.0, 1, 6.9])
    func staleness_recentWithinAWeek(daysAgo: Double) {
        #expect(backup(daysAgo: daysAgo).staleness(at: now, calendar: calendar()) == .recent)
    }

    @Test(arguments: [7.0, 10, 29.9])
    func staleness_staleWithin30Days(daysAgo: Double) {
        #expect(backup(daysAgo: daysAgo).staleness(at: now, calendar: calendar()) == .stale)
    }

    @Test(arguments: [30.0, 100, 1000])
    func staleness_veryStaleAfter30Days(daysAgo: Double) {
        #expect(backup(daysAgo: daysAgo).staleness(at: now, calendar: calendar()) == .veryStale)
    }

    /// A clock that's gone backwards since the backup doesn't make it stale.
    @Test
    func staleness_backupInTheFutureIsRecent() {
        #expect(backup(daysAgo: -3).staleness(at: now, calendar: calendar()) == .recent)
    }

    /// Staleness goes by when the backup was made, not when it was last exported or imported.
    @Test
    func staleness_usesBackupDateNotEventDate() {
        let event = VaultBackupEvent(
            backupDate: now.addingTimeInterval(-100 * 24 * 60 * 60),
            eventDate: now,
            kind: .importedToPDF,
            payloadHash: .init(value: Data(repeating: 0xAB, count: 32)),
        )

        #expect(event.staleness(at: now, calendar: calendar()) == .veryStale)
    }
}

// MARK: - Helpers

extension VaultBackupEventTests {
    private func backup(daysAgo: Double) -> VaultBackupEvent {
        let date = now.addingTimeInterval(-daysAgo * 24 * 60 * 60)
        return VaultBackupEvent(
            backupDate: date,
            eventDate: date,
            kind: .exportedToPDF,
            payloadHash: .init(value: Data(repeating: 0xAB, count: 32)),
        )
    }

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
}
