import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultSettings
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class BackupKeyChangeViewSnapshotTests {
    @Test
    func layout() {
        snapshotScenarios {
            BackupKeyChangeView(viewModel: makeViewModel())
        }
    }

    @Test
    func layoutAuthenticated() {
        snapshotScenarios {
            let viewModel = makeViewModel()
            viewModel.permissionState = .allowed
            return BackupKeyChangeView(viewModel: viewModel)
        }
    }
}

// MARK: - Helpers

extension BackupKeyChangeViewSnapshotTests {
    private func makeViewModel() -> BackupKeyChangeViewModel {
        BackupKeyChangeViewModel(
            dataModel: anyVaultDataModel(),
            authenticationService: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            deriverFactory: VaultKeyDeriverFactoryImpl(),
        )
    }

    /// Builds a fresh view for every scenario.
    ///
    /// The view resets `permissionState` to `.undetermined` in `onDisappear`, so sharing one view —
    /// and therefore one view model — across the loop let the first snapshot tear down the state that
    /// the remaining five depended on. Every scenario now gets its own instance.
    private func snapshotScenarios(
        deviceAuthenticationPolicy: some DeviceAuthenticationPolicy = DeviceAuthenticationPolicyAlwaysAllow(),
        testName: String = #function,
        makeView: () -> some View,
    ) {
        let colorSchemes: [ColorScheme] = [.light, .dark]
        let dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge]
        for colorScheme in colorSchemes {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = makeView()
                    .dynamicTypeSize(dynamicTypeSize)
                    .preferredColorScheme(colorScheme)
                    .framedForTest()
                    .environment(makePasteboard())
                    .environment(DeviceAuthenticationService(policy: deviceAuthenticationPolicy))
                let named = "\(colorScheme)_\(dynamicTypeSize)"

                assertSnapshot(
                    of: snapshottingView,
                    as: .image,
                    named: named,
                    testName: testName,
                )
            }
        }
    }

    private func makePasteboard() -> Pasteboard {
        Pasteboard(SystemPasteboardMock(), localSettings: LocalSettings(defaults: .init(userDefaults: .standard)))
    }
}
