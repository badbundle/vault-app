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
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backupExclusion = VaultStorageBackupExclusion(directory: directory, settings: appLock)
        backupExclusion.apply()

        #expect(settings.state.hidesVaultWhileScreenCaptured)
        #expect(!settings.state.allowUniversalClipboardForOTPs)
        #expect(!settings.state.allowUniversalClipboardForNotes)
        #expect(settings.state.pasteTimeToLive == .default)
        #expect(settings.state.codeTapAction == .copy)
        #expect(!settings.state.showsNextCode)
        #expect(!settings.state.lockNewItems)
        #expect(appLock.delay == .immediately)
        #expect(!appLock.erasesAfterFailedPasswords)
        // The Mac's own: Keep Out of Time Machine, on until the user turns it off, as C7 has it.
        #expect(try !appLock.loadIncludesVaultInBackups())
        #expect(backupExclusion.isExcluded)
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
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Kept out of Time Machine, as it is until the user turns it off.
        let backupExclusion = VaultStorageBackupExclusion(directory: directory, settings: lockSettings)
        backupExclusion.apply()
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
            backupExclusion: backupExclusion,
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

    /// A new, empty directory, standing in for the App Group's container. The caller removes it.
    private static func temporaryDirectory() throws -> URL {
        let directory = URL.temporaryDirectory.appending(
            path: "Settings-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Help opens on recovery phrases and private keys, with the page about codes below them.
    @Test
    func helpQuestions_startWithRecoveryPhrasesAndPrivateKeys() {
        #expect(VaultMacHelpPage.questions.prefix(3) == [.recoveryPhrases, .privateKeys, .codes])
        #expect(VaultMacHelpModel().selection == .recoveryPhrases)
    }

    @Test
    func helpPages_allHaveTheirText() {
        for page in VaultMacHelpPage.allCases where ![.libraries, .openSource].contains(page) {
            #expect(page.document != nil, "\(page)")
        }
    }
}
