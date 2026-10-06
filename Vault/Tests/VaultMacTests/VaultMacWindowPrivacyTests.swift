import AppKit
import Foundation
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultMac

@MainActor
struct VaultMacWindowPrivacyTests {
    @Test
    func apply_withHideWhileRecording_keepsTheWindowOutOfEveryCapture() async throws {
        let env = try await Environment()
        let window = makeWindow()

        env.privacy.apply(to: window)

        #expect(env.settings.state.hidesVaultWhileScreenCaptured)
        #expect(window.sharingType == .none)
    }

    @Test
    func apply_withoutHideWhileRecording_givesTheSystemsDefault() async throws {
        let env = try await Environment()
        env.settings.state.hidesVaultWhileScreenCaptured = false
        let window = makeWindow()
        window.sharingType = .none

        env.privacy.apply(to: window)

        #expect(window.sharingType == .readOnly)
    }

    @Test
    func apply_windowIsNeverRestoredOrATab() async throws {
        let env = try await Environment()
        let window = makeWindow()
        window.isRestorable = true
        window.tabbingMode = .preferred

        env.privacy.apply(to: window)

        #expect(!window.isRestorable)
        #expect(window.tabbingMode == .disallowed)
    }

    @Test
    func start_makesTheWindowsAlreadyOpenPrivate() async throws {
        let env = try await Environment()
        let windows = [makeWindow(), makeWindow()]

        env.privacy.start(windows: windows)

        #expect(windows.map(\.sharingType) == [.none, .none])
    }

    /// A sheet or alert updates as it appears, and every window does as it's drawn again.
    @Test
    func windowUpdating_makesItPrivate() async throws {
        let env = try await Environment()
        env.privacy.start(windows: [])
        let window = makeWindow()

        env.center.post(name: NSWindow.didUpdateNotification, object: window)

        #expect(window.sharingType == .none)
        #expect(!window.isRestorable)
    }

    @Test
    func turningHideWhileRecordingOff_reachesAWindowAsItUpdates() async throws {
        let env = try await Environment()
        let window = makeWindow()
        env.privacy.start(windows: [window])
        #expect(window.sharingType == .none)

        env.settings.state.hidesVaultWhileScreenCaptured = false
        env.center.post(name: NSWindow.didUpdateNotification, object: window)

        #expect(window.sharingType == .readOnly)
    }

    @Test
    func minimisingAWindow_locksVaultFirst() async throws {
        let env = try await Environment()
        env.privacy.start(windows: [])

        env.center.post(name: NSWindow.willMiniaturizeNotification, object: makeWindow())

        #expect(env.appLock.isLocked)
    }

    @Test
    func minimisingAWindow_hidesItsContentsUntilItsBack() async throws {
        let env = try await Environment()
        env.privacy.start(windows: [])
        let window = makeWindow()
        window.contentView = NSView()

        env.center.post(name: NSWindow.willMiniaturizeNotification, object: window)
        #expect(window.contentView?.isHidden == true)

        env.center.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        #expect(window.contentView?.isHidden == false)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true,
        )
    }

    @MainActor
    private struct Environment {
        let settings: LocalSettings
        let appLock: AppLockService
        let center = NotificationCenter()
        let privacy: VaultMacWindowPrivacy

        init() async throws {
            settings = try LocalSettings(defaults: .nonPersistent())
            let lockSettings = try AppLockSettingsStore(userDefaults: .nonPersistent())
            lockSettings.isEnabled = true
            appLock = AppLockService(
                settings: lockSettings,
                authenticationService: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
                passwordService: FakeAppLockPasswordService(password: "password"),
                purgeSensitiveData: {},
            )
            await appLock.unlock()
            await appLock.unlock(password: "password")
            #expect(!appLock.isLocked)
            privacy = VaultMacWindowPrivacy(localSettings: settings, appLock: appLock, center: center)
        }
    }
}

/// Nothing in the Mac app names a window after what it shows, so window titles, the Window menu and Mission Control
/// only ever say "Vault".
struct VaultMacWindowTitleDeclarationTests {
    static let titleModifiers = [".navigationTitle(", ".navigationSubtitle(", ".navigationDocument("]

    @Test
    func nothingSetsAWindowTitleFromWhatItShows() throws {
        let uses = try VaultMacTextInputDeclarationTests.lines(in: VaultMacTextInputDeclarationTests.macSources())
            .filter { line in
                Self.titleModifiers.contains { line.code.contains($0) }
                    || (line.code.contains(".title = ") && !line.code.contains("self.title = "))
            }

        #expect(
            uses.isEmpty,
            """
            A window's title is only ever "Vault" (docs/mac-app.md, "Other ways a window's contents could leak"). On:
            \(uses.map(\.description).joined(separator: "\n"))
            """,
        )
    }
}
