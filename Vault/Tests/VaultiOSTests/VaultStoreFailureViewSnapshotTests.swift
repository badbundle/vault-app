import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultiOS

@MainActor
final class VaultStoreFailureViewSnapshotTests {
    @Test
    func layout() {
        let colorSchemes: [ColorScheme] = [.light, .dark]
        let dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge]
        for colorScheme in colorSchemes {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = VaultStoreFailureView(
                    message: "Unable to connect to PersistedLocalVaultStore",
                )
                .dynamicTypeSize(dynamicTypeSize)
                .preferredColorScheme(colorScheme)
                .framedForTest()
                let named = "\(colorScheme)_\(dynamicTypeSize)"

                assertSnapshot(
                    of: snapshottingView,
                    as: .image,
                    named: named,
                )
            }
        }
    }

    @Test
    func layoutWithoutDetails() {
        let snapshottingView = VaultStoreFailureView(message: nil)
            .dynamicTypeSize(.medium)
            .preferredColorScheme(.light)
            .framedForTest()

        assertSnapshot(of: snapshottingView, as: .image)
    }
}
