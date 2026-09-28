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

    /// The decrypted backup, with what importing it will do and a button named for it. Replacing is in red.
    @Test
    func layoutReady() async {
        for context in [BackupImportContext.toEmptyVault, .merge, .override] {
            await snapshotScenarios(named: "\(context)") {
                makeReadyView(viewModel: makeViewModel(context: context))
            }
        }
    }

    @Test
    func layoutImported() async {
        for context in [BackupImportContext.toEmptyVault, .merge, .override] {
            await snapshotScenarios(named: "\(context)") {
                let viewModel = makeViewModel(context: context)
                await viewModel.importPayload(payload: anyPayload())
                #expect(viewModel.importState == .success)
                return makeReadyView(viewModel: viewModel)
            }
        }
    }

    /// The error takes the header's place, with the button still there to try again.
    @Test
    func layoutImportFailed() async {
        for context in [BackupImportContext.toEmptyVault, .merge, .override] {
            await snapshotScenarios(named: "\(context)") {
                let importer = VaultStoreImporterMock()
                importer.importAndMergeVaultHandler = { _ in throw TestError() }
                importer.importAndOverrideVaultHandler = { _ in throw TestError() }
                let viewModel = makeViewModel(context: context, dataModel: anyVaultDataModel(vaultImporter: importer))
                await viewModel.importPayload(payload: anyPayload())
                return makeReadyView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Helpers

extension BackupImportFlowViewSnapshotTests {
    private func makeViewModel(
        context: BackupImportContext,
        dataModel: VaultDataModel = anyVaultDataModel(),
    ) -> BackupImportFlowViewModel {
        BackupImportFlowViewModel(importContext: context, dataModel: dataModel)
    }

    /// The screen pushed once the backup is decrypted, in a navigation stack for its Done button.
    private func makeReadyView(viewModel: BackupImportFlowViewModel) -> some View {
        NavigationStack {
            BackupImportReadyView(viewModel: viewModel, payload: anyPayload(), close: {})
        }
    }

    private func anyPayload() -> VaultApplicationPayload {
        VaultApplicationPayload(userDescription: "", items: [], tags: [])
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
