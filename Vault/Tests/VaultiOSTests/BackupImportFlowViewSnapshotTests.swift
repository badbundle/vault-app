import Foundation
import FoundationExtensions
import PDFKit
import SwiftUI
import TestHelpers
import Testing
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class BackupImportFlowViewSnapshotTests {
    /// The header says what's about to happen to the vault, with the Restore page's symbol for it.
    @Test
    func layout() async {
        for context in [BackupImportContext.toEmptyVault, .merge, .override] {
            await snapshotScenarios(named: "\(context)") {
                BackupImportFlowView(viewModel: makeViewModel(context: context))
            }
        }
    }

    /// A PDF that isn't a Vault backup: the error takes the header's place, in red.
    @Test
    func layoutError() async throws {
        let pdfData = try nonBackupPDFData()
        await snapshotScenarios {
            let viewModel = makeViewModel(context: .merge)
            await viewModel.handleImport(fromPDF: .success(pdfData))
            return BackupImportFlowView(viewModel: viewModel)
        }
    }
}

// MARK: - Helpers

extension BackupImportFlowViewSnapshotTests {
    private func makeViewModel(context: BackupImportContext) -> BackupImportFlowViewModel {
        BackupImportFlowViewModel(importContext: context, dataModel: anyVaultDataModel())
    }

    /// A PDF with a blank page, and no backup attached.
    private func nonBackupPDFData() throws -> Data {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        return try #require(document.dataRepresentation())
    }

    /// Snapshots a fresh view in each appearance, at the smallest, default and a large text size.
    private func snapshotScenarios(
        named name: String? = nil,
        testName: String = #function,
        makeView: () async -> some View,
    ) async {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                let snapshottingView = await makeView()
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest()
                    .environment(anyVaultInjector())
                let scenario = "\(colorScheme)_\(dynamicTypeSize)"

                assertSnapshot(
                    of: snapshottingView,
                    colorScheme: colorScheme,
                    named: name.map { "\($0)_\(scenario)" } ?? scenario,
                    testName: testName,
                )
            }
        }
    }
}
