import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class SettingsDangerViewSnapshotTests {
    @Test
    func layout() {
        let colorSchemes: [ColorScheme] = [.light, .dark]
        let dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge]
        for colorScheme in colorSchemes {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = SettingsDangerView(viewModel: makeViewModel())
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest()
                let named = "\(colorScheme)_\(dynamicTypeSize)"

                assertSnapshot(
                    of: snapshottingView,
                    colorScheme: colorScheme,
                    named: named,
                )
            }
        }
    }
}

// MARK: - Helpers

extension SettingsDangerViewSnapshotTests {
    private func makeViewModel() -> SettingsDangerViewModel {
        SettingsDangerViewModel(
            dataModel: anyVaultDataModel(),
            authenticationService: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
        )
    }
}
