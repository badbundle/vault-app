import Foundation
import SwiftUI
import TestHelpers
import Testing
import UIKit
import VaultFeed
import VaultiOS
import VaultSettings
@testable import VaultiOSAutofill

/// The AutoFill sheet with the vault encrypted, as the extension sets it up for a request.
@MainActor
struct VaultAutofillViewSnapshotTests {
    /// Finding out whether there's the memory to unlock, before anything is asked. It can be cancelled.
    @Test(arguments: [ColorScheme.light, .dark])
    func encryptedVault_checking(colorScheme: ColorScheme) throws {
        let viewModel = try makeViewModel(headroom: .neverAnswers)

        snapshot(viewModel, colorScheme: colorScheme)
    }

    /// The App Lock Password after device authentication, never Face ID alone.
    @Test(arguments: [ColorScheme.light, .dark])
    func encryptedVault_password(colorScheme: ColorScheme) async throws {
        let viewModel = try makeViewModel(headroom: .enough)
        await viewModel.prepareToUnlock()
        await viewModel.appLock.unlock()

        snapshot(viewModel, colorScheme: colorScheme)
    }

    /// A vault AutoFill can't open, such as with the password turned off or a change underway, sends the user to
    /// Vault too.
    @Test(arguments: [ColorScheme.light, .dark])
    func unavailableVault(colorScheme: ColorScheme) throws {
        let viewModel = try VaultAutofillViewModel(
            localSettings: LocalSettings(defaults: .nonPersistent()),
            storage: .unavailable,
            appLockSettings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            purgeVaultContents: {},
        )
        viewModel.show(feature: .showAllCodesSelector)

        snapshot(viewModel, colorScheme: colorScheme)
    }

    /// Without the memory to derive the key, the sheet sends the user to Vault.
    @Test(arguments: [ColorScheme.light, .dark])
    func encryptedVault_notEnoughMemory(colorScheme: ColorScheme) async throws {
        let viewModel = try makeViewModel(headroom: .notEnough)
        await viewModel.prepareToUnlock()

        snapshot(viewModel, colorScheme: colorScheme)
    }
}

// MARK: - Helpers

extension VaultAutofillViewSnapshotTests {
    private func makeViewModel(headroom: FakeAutofillPasswordService.Headroom) throws -> VaultAutofillViewModel {
        let viewModel = try VaultAutofillViewModel(
            localSettings: LocalSettings(defaults: .nonPersistent()),
            storage: .encrypted(FakeAutofillPasswordService(headroom: headroom)),
            appLockSettings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            purgeVaultContents: {},
        )
        viewModel.show(feature: .showAllCodesSelector)
        return viewModel
    }

    private func snapshot(
        _ viewModel: VaultAutofillViewModel,
        colorScheme: ColorScheme,
        testName: String = #function,
    ) {
        let view = VaultAutofillView(
            viewModel: viewModel,
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            generator: VaultItemPreviewViewGeneratorMock(),
        )
        // Not yet active, so it doesn't ask for Face ID while it's drawn.
        .environment(\.scenePhase, .inactive)
        .environment(\.drawsGlassSnapshotBackdrop, true)
        .environment(\.colorScheme, colorScheme)
        .framedForTest(height: 844)
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)

        assertSnapshot(of: view, as: .image(traits: traits), named: "\(colorScheme)", testName: testName)
    }
}
