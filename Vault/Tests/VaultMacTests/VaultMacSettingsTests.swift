import AppKit
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultMac

/// The Settings window starts at iOS's defaults, which keep everything on this Mac and locked (C7).
@MainActor
struct VaultMacSettingsTests {
    @Test
    func defaults_areiOSs() throws {
        let settings = try LocalSettings(defaults: .nonPersistent())
        let appLock = try AppLockSettingsStore(userDefaults: .nonPersistent())

        #expect(settings.state.hidesVaultWhileScreenCaptured)
        #expect(!settings.state.allowUniversalClipboardForOTPs)
        #expect(!settings.state.allowUniversalClipboardForNotes)
        #expect(settings.state.pasteTimeToLive == .default)
        #expect(settings.state.codeTapAction == .copy)
        #expect(!settings.state.showsNextCode)
        #expect(!settings.state.lockNewItems)
        #expect(appLock.delay == .immediately)
        #expect(!appLock.erasesAfterFailedPasswords)
    }

    @Test(arguments: MacAppearance.allCases)
    func general(appearance: MacAppearance) throws {
        let view = try VaultMacGeneralSettings(localSettings: LocalSettings(defaults: .nonPersistent()))

        assertSnapshot(
            of: view,
            as: .macWindow(
                width: VaultMacSettingsView.width,
                height: VaultMacSettingsView.generalHeight,
                appearance: appearance.name,
            ),
            named: appearance.rawValue,
        )
    }

    @Test(arguments: MacAppearance.allCases)
    func security(appearance: MacAppearance) throws {
        let (dataModel, _) = try MacTestVault.make()
        let authentication = DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow())
        let lockSettings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        lockSettings.isEnabled = true
        let view = try VaultMacSecuritySettings(
            localSettings: LocalSettings(defaults: .nonPersistent()),
            appLock: AppLockService(
                settings: lockSettings,
                authenticationService: authentication,
                passwordService: FakeAppLockPasswordService(password: "password"),
                purgeSensitiveData: {},
            ),
            dataModel: dataModel,
            authentication: authentication,
        )

        assertSnapshot(
            of: view,
            as: .macWindow(
                width: VaultMacSettingsView.width,
                height: VaultMacSettingsView.securityHeight,
                appearance: appearance.name,
            ),
            named: appearance.rawValue,
        )
    }

    @Test
    func changePasswordForm() throws {
        let lockSettings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        lockSettings.isEnabled = true
        let appLock = AppLockService(
            settings: lockSettings,
            authenticationService: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            passwordService: FakeAppLockPasswordService(password: "password"),
            purgeSensitiveData: {},
        )
        let view = VaultMacAppLockPasswordForm(
            viewModel: AppLockPasswordFormViewModel(purpose: .change, appLock: appLock),
            close: {},
        )

        assertSnapshot(of: view, as: .macWindow(width: 480, height: 420))
    }

    @Test
    func helpPages_allHaveTheirText() {
        for page in VaultMacHelpPage.allCases where ![.libraries, .openSource].contains(page) {
            #expect(page.document != nil, "\(page)")
        }
    }
}
