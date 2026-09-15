import Foundation
import FoundationExtensions
import SwiftUI
import TestHelpers
import Testing
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class BackupImportFlowViewSnapshotTests {
    @Test
    func layout() {
        for context in [BackupImportContext.toEmptyVault, .merge, .override] {
            for colorScheme in [ColorScheme.light, .dark] {
                let snapshottingView = BackupImportFlowView(viewModel: makeViewModel(context: context))
                    .dynamicTypeSize(.medium)
                    .preferredColorScheme(colorScheme)
                    .framedForTest()
                    .environment(anyVaultInjector())

                assertSnapshot(
                    of: snapshottingView,
                    as: .image,
                    named: "\(context)_\(colorScheme)",
                )
            }
        }
    }
}

// MARK: - Helpers

extension BackupImportFlowViewSnapshotTests {
    private func makeViewModel(context: BackupImportContext) -> BackupImportFlowViewModel {
        BackupImportFlowViewModel(
            importContext: context,
            dataModel: anyVaultDataModel(),
            existingBackupPassword: nil,
            encryptedVaultDecoder: EncryptedVaultDecoderMock(),
        )
    }
}
