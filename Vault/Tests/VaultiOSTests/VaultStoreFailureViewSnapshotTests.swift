import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
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

    /// The password is off, and the device key isn't on this device, as after an unencrypted backup is restored onto
    /// another iPhone.
    @Test
    func layoutDeviceKeyMissing() {
        for colorScheme in [ColorScheme.light, .dark] {
            let snapshottingView = VaultStoreFailureView(
                reason: .deviceKeyMissing,
                message: "The operation couldn't be completed. (VaultFeed.VaultStorageRecovery.Failure error 3.)",
            )
            .dynamicTypeSize(.medium)
            .framedForTest()

            assertSnapshot(of: snapshottingView, colorScheme: colorScheme, named: "\(colorScheme)")
        }
    }

    /// The vault's data is missing and nothing shows it was erased on purpose: the way to restore it, and a way to
    /// erase and start again that asks first.
    @Test
    func layoutVaultMissing() {
        for colorScheme in [ColorScheme.light, .dark] {
            let snapshottingView = VaultStoreFailureView(
                reason: .vaultMissing,
                message: "The operation couldn't be completed. (VaultFeed.VaultStorageRecovery.Failure error 5.)",
                missingVault: MissingVaultViewModel(erase: {}),
            )
            .dynamicTypeSize(.medium)
            .framedForTest()

            assertSnapshot(of: snapshottingView, colorScheme: colorScheme, named: "\(colorScheme)")
        }
    }

    @Test
    func layoutWithoutDetails() {
        let snapshottingView = VaultStoreFailureView(message: nil)
            .dynamicTypeSize(.medium)
            .framedForTest()

        assertSnapshot(of: snapshottingView, colorScheme: .light)
    }
}
