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
        let sut = try makeSUT()

        assertSnapshot(of: sut, colorScheme: .dark)
    }

    @Test
    func layout_largeText() throws {
        let sut = try makeSUT(dynamicTypeSize: .accessibility2, height: 1600)

        assertSnapshot(of: sut, as: .image)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func universalClipboardOn(colorScheme: ColorScheme) throws {
        let sut = try makeSUT { state in
            state.allowUniversalClipboardForOTPs = true
        }

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func appLockOn(colorScheme: ColorScheme) throws {
        let sut = try makeSUT(isAppLockEnabled: true)

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func appLockWithoutPasscode(colorScheme: ColorScheme) throws {
        let sut = try makeSUT(policy: .cannotAuthenticate)

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }
}

// MARK: - Helpers

extension VaultSettingsViewSnapshotTests {
    private func makeSUT(
        dynamicTypeSize: DynamicTypeSize = .medium,
        height: CGFloat = 1200,
        isAppLockEnabled: Bool = false,
        policy: some DeviceAuthenticationPolicy = .alwaysDeny,
        configure: (inout LocalSettingsState) -> Void = { _ in },
    ) throws -> some View {
        let localSettings = try LocalSettings(defaults: .nonPersistent())
        configure(&localSettings.state)
        let authenticationService = DeviceAuthenticationService(policy: policy)
        let appLockSettings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        appLockSettings.isEnabled = isAppLockEnabled
        let appLock = AppLockService(
            settings: appLockSettings,
            authenticationService: authenticationService,
            purgeSensitiveData: {},
        )
        return VaultSettingsView(viewModel: .init(), localSettings: localSettings)
            .environment(anyVaultDataModel())
            .environment(authenticationService)
            .environment(appLock)
            .dynamicTypeSize(dynamicTypeSize)
            .framedForTest(height: height)
    }
}
