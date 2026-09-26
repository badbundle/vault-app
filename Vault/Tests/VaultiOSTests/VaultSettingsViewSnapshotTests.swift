import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
struct VaultSettingsViewSnapshotTests {
    @Test
    func layout() throws {
        let sut = try makeSUT()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_dark() throws {
        // Not `preferredColorScheme`: that sets the test host's window, where it outlasts this snapshot.
        let sut = try makeSUT()
            .environment(\.colorScheme, .dark)

        // The environment alone doesn't reach the form's UIKit-backed rows; the host's traits do.
        assertSnapshot(of: sut, as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }

    @Test
    func layout_largeText() throws {
        let sut = try makeSUT(dynamicTypeSize: .accessibility2, height: 1600)

        assertSnapshot(of: sut, as: .image)
    }
}

// MARK: - Helpers

extension VaultSettingsViewSnapshotTests {
    private func makeSUT(dynamicTypeSize: DynamicTypeSize = .medium, height: CGFloat = 1200) throws -> some View {
        let localSettings = try LocalSettings(defaults: .nonPersistent())
        return VaultSettingsView(viewModel: .init(), localSettings: localSettings)
            .environment(anyVaultDataModel())
            .environment(DeviceAuthenticationService(policy: .alwaysDeny))
            .dynamicTypeSize(dynamicTypeSize)
            .framedForTest(height: height)
    }
}
