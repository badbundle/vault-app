import CryptoEngine
import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct LastBackupSummaryViewSnapshotTests {
    /// Pinned reference instant so the staleness thresholds are deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func noBackup() {
        let sut = makeSUT(lastBackup: nil)

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func recentBackup() {
        let sut = makeSUT(lastBackup: event(daysAgo: 1))

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func agingBackup() {
        let sut = makeSUT(lastBackup: event(daysAgo: 10))

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func staleBackup() {
        let sut = makeSUT(lastBackup: event(daysAgo: 100))

        assertSnapshot(of: sut, as: .image)
    }
}

extension LastBackupSummaryViewSnapshotTests {
    private func makeSUT(lastBackup: VaultBackupEvent?) -> some View {
        List {
            LastBackupSummaryView(lastBackup: lastBackup, now: now)
                .listRowInsets(EdgeInsets())
        }
        .framedForTest()
    }

    private func event(daysAgo: Int) -> VaultBackupEvent {
        let backupDate = now.addingTimeInterval(-Double(daysAgo) * 24 * 60 * 60)
        return VaultBackupEvent(
            backupDate: backupDate,
            eventDate: backupDate,
            kind: .exportedToPDF,
            payloadHash: .init(value: Data(repeating: 0xAB, count: 32)),
        )
    }
}
