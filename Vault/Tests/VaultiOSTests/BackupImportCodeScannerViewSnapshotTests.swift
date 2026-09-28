import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class BackupImportCodeScannerViewSnapshotTests {
    /// Some of the codes scanned, in no particular order: the headline under the camera, the count, and a tick for each
    /// one.
    @Test
    func layoutPartiallyScanned() async {
        await snapshotScenarios {
            let handler = BackupImportScanningHandler()
            for index in [0, 2, 5] {
                _ = handler.decode(data: shard(index: index, of: 8))
            }
            return makeView(handler: handler)
        }
    }
}

// MARK: - Helpers

extension BackupImportCodeScannerViewSnapshotTests {
    private func makeView(handler: BackupImportScanningHandler) -> some View {
        // In a navigation stack, for the title and Cancel.
        NavigationStack {
            BackupImportCodeScannerView(
                intervalTimer: IntervalTimerMock(),
                handler: handler,
                loadedEncryptedVault: { _ in },
            )
        }
    }

    /// One of a backup's codes. Only its place in the group matters here, not what it carries.
    private func shard(index: Int, of total: Int) -> String {
        """
        {
            "G":{"ID":10,"N":\(total),"I":\(index)},
            "D": "AA=="
        }
        """
    }

    /// Snapshots a fresh view in each appearance, at the smallest, default and a large text size.
    private func snapshotScenarios(
        testName: String = #function,
        makeView: () async -> some View,
    ) async {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                let snapshottingView = await makeView()
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest()

                assertSnapshot(
                    of: snapshottingView,
                    colorScheme: colorScheme,
                    named: "\(colorScheme)_\(dynamicTypeSize)",
                    testName: testName,
                )
            }
        }
    }
}
