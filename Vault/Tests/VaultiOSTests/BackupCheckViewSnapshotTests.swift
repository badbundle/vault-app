import Foundation
import PDFKit
import SwiftUI
import TestHelpers
import Testing
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class BackupCheckViewSnapshotTests {
    /// What the check does, and where the backup can come from.
    @Test
    func layout() async {
        await snapshotScenarios {
            BackupCheckView(viewModel: BackupCheckViewModel())
        }
    }

    /// A PDF that isn't a Vault backup: the error takes the header's place, in red.
    @Test
    func layoutError() async throws {
        let pdfData = try nonBackupPDFData()
        await snapshotScenarios {
            let viewModel = BackupCheckViewModel()
            await viewModel.check(pdf: .success(pdfData))
            return BackupCheckView(viewModel: viewModel)
        }
    }

    /// The backup opened: the header says so in green, and nothing about what's in it.
    @Test
    func layoutOpened() async {
        await snapshotScenarios {
            let viewModel = BackupCheckViewModel()
            viewModel.backupDidOpen()
            return BackupCheckView(viewModel: viewModel)
        }
    }
}

// MARK: - Helpers

extension BackupCheckViewSnapshotTests {
    /// A PDF with a blank page, and no backup attached.
    private func nonBackupPDFData() throws -> Data {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        return try #require(document.dataRepresentation())
    }

    /// Snapshots a fresh view in a navigation stack, for its title, in each appearance, at the smallest, default and a
    /// large text size.
    private func snapshotScenarios(
        testName: String = #function,
        makeView: () async -> some View,
    ) async {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                let view = await makeView()
                let snapshottingView = NavigationStack { view }
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest()
                    .environment(anyVaultInjector())

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
