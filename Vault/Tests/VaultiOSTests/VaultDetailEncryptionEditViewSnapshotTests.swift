import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultiOS

@MainActor
final class VaultDetailEncryptionEditViewSnapshotTests {
    @Test
    func layoutEncryptionDisabled() {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                let snapshottingView = makeView(encryptionInitiallyEnabled: false)
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest()

                assertSnapshot(
                    of: snapshottingView,
                    colorScheme: colorScheme,
                    named: "\(colorScheme)_\(dynamicTypeSize)",
                )
            }
        }
    }

    @Test
    func layoutEncryptionEnabled() {
        for colorScheme in [ColorScheme.light, .dark] {
            let snapshottingView = makeView(encryptionInitiallyEnabled: true)
                .dynamicTypeSize(.medium)
                .framedForTest()

            assertSnapshot(
                of: snapshottingView,
                colorScheme: colorScheme,
                named: "\(colorScheme)_medium",
            )
        }
    }

    @Test
    func layoutEncryptionRequiredNoPassword() {
        for colorScheme in [ColorScheme.light, .dark] {
            let snapshottingView = makeRequiredView(hasExistingPassword: false)
                .dynamicTypeSize(.medium)
                .framedForTest()

            assertSnapshot(
                of: snapshottingView,
                colorScheme: colorScheme,
                named: "\(colorScheme)_medium",
            )
        }
    }

    @Test
    func layoutEncryptionRequiredExistingPassword() {
        for colorScheme in [ColorScheme.light, .dark] {
            let snapshottingView = makeRequiredView(hasExistingPassword: true)
                .dynamicTypeSize(.medium)
                .framedForTest()

            assertSnapshot(
                of: snapshottingView,
                colorScheme: colorScheme,
                named: "\(colorScheme)_medium",
            )
        }
    }
}

// MARK: - Helpers

extension VaultDetailEncryptionEditViewSnapshotTests {
    private func makeView(encryptionInitiallyEnabled: Bool) -> some View {
        VaultDetailEncryptionEditView(
            title: "Encryption",
            description: "Encrypt this item with a separate password.",
            encryptionInitiallyEnabled: encryptionInitiallyEnabled,
            didSetNewEncryptionPassword: { _ in },
            didRemoveEncryption: {},
        )
    }

    private func makeRequiredView(hasExistingPassword: Bool) -> some View {
        VaultDetailEncryptionEditView(
            title: "Password",
            description: "This item is always encrypted.",
            hasExistingPassword: hasExistingPassword,
            didSetNewEncryptionPassword: { _ in },
        )
    }
}
