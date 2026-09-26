import CryptoEngine
import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct LastBackupHeaderSnapshotTests {
    /// Pinned reference instant so the staleness thresholds are deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func noBackup() {
        assertSnapshots(lastBackup: nil)
    }

    @Test
    func recentBackup() {
        assertSnapshots(lastBackup: event(daysAgo: 1))
    }

    @Test
    func staleBackup() {
        assertSnapshots(lastBackup: event(daysAgo: 10))
    }

    @Test
    func veryStaleBackup() {
        assertSnapshots(lastBackup: event(daysAgo: 100))
    }

    @Test
    func recentBackup_largeText() {
        let sut = Form {
            Section {
                LastBackupHeader(lastBackup: event(daysAgo: 1), now: now)
            }
        }
        .dynamicTypeSize(.accessibility2)
        .framedForTest(height: 600)

        assertSnapshot(of: sut, colorScheme: .light)
    }
}

extension LastBackupHeaderSnapshotTests {
    private func assertSnapshots(
        lastBackup: VaultBackupEvent?,
        testName: String = #function,
        line: UInt = #line,
    ) {
        for colorScheme in [ColorScheme.light, .dark] {
            let sut = Form {
                Section {
                    LastBackupHeader(lastBackup: lastBackup, now: now)
                }
            }
            .framedForTest(height: 300)

            assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)", testName: testName, line: line)
        }
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
