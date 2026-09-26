import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct AppLockViewSnapshotTests {
    @Test
    func locked() {
        snapshotScenarios(
            view: AppLockView(state: .init(step: .deviceAuthentication)) {},
            dynamicTypeSizes: [.xSmall, .medium, .xxLarge, .accessibility3],
        )
    }

    @Test
    func unlocking() {
        snapshotScenarios(view: AppLockView(state: .init(step: .deviceAuthentication, isInProgress: true)) {})
    }

    @Test
    func authenticationFailed() {
        snapshotScenarios(view: AppLockView(state: .init(step: .deviceAuthentication, failure: .failed)) {})
    }

    @Test
    func noPasscode() {
        snapshotScenarios(view: AppLockView(state: .init(step: .deviceAuthentication, failure: .unavailable)) {})
    }

    // MARK: - App Lock Password

    @Test
    func passwordEntry() {
        snapshotScenarios(
            view: AppLockView(state: .init(step: .password)) {},
            dynamicTypeSizes: [.xSmall, .medium, .xxLarge, .accessibility3],
        )
    }

    @Test
    func passwordChecking() {
        snapshotScenarios(view: AppLockView(state: .init(step: .password, isInProgress: true)) {})
    }

    @Test
    func wrongPassword() {
        snapshotScenarios(view: AppLockView(state: .init(step: .password, failure: .wrongPassword)) {})
    }

    /// Only how long to wait, never how many attempts are left.
    @Test
    func wrongPasswordWaiting() {
        let state = AppLockedState(
            step: .password,
            failure: .wrongPassword,
            passwordRetryAt: .now.advanced(by: .seconds(5 * 60)),
        )
        snapshotScenarios(view: AppLockView(state: state) {})
    }

    /// Back at the lock screen with the wait not over yet.
    @Test
    func passwordWaiting() {
        let state = AppLockedState(step: .password, passwordRetryAt: .now.advanced(by: .seconds(60 * 60)))
        snapshotScenarios(view: AppLockView(state: state) {})
    }

    @Test
    func passwordCouldNotBeChecked() {
        snapshotScenarios(view: AppLockView(state: .init(step: .password, failure: .failed)) {})
    }

    // MARK: - Covers

    @Test
    func privacyCover() {
        snapshotScenarios(view: AppPrivacyCoverView(), dynamicTypeSizes: [.medium])
    }

    @Test
    func screenCaptureCover() {
        snapshotScenarios(view: AppScreenCaptureCoverView(), dynamicTypeSizes: [.medium, .xxLarge, .accessibility3])
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func lockedLandscape(colorScheme: ColorScheme) {
        let view = AppLockView(state: .init(step: .deviceAuthentication)) {}
            .framedForLandscapeTest()

        assertSnapshot(of: view, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func autofillGate(colorScheme: ColorScheme) throws {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.isEnabled = true
        let appLock = AppLockService(
            settings: settings,
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            purgeSensitiveData: {},
        )
        let view = NavigationStack {
            AppLockGate(appLock: appLock, cancel: {}) {
                Text("Codes")
            }
        }
        // Not yet active, so it doesn't ask for Face ID while it's drawn.
        .environment(\.scenePhase, .inactive)
        .framedForTest(height: 844)

        assertSnapshot(of: view, colorScheme: colorScheme, named: "\(colorScheme)")
    }
}

// MARK: - AutoFill with an encrypted vault

extension AppLockViewSnapshotTests {
    /// The AutoFill sheet asks for the App Lock Password after device authentication, as the app does.
    @Test(arguments: [ColorScheme.light, .dark])
    func autofillGatePassword(colorScheme: ColorScheme) async throws {
        let appLock = try AppLockService(
            settings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            passwordService: FakeAppLockPasswordService(password: "correct horse"),
            purgeSensitiveData: {},
        )
        await appLock.unlock()
        let view = NavigationStack {
            AppLockGate(appLock: appLock, cancel: {}) {
                Text("Codes")
            }
        }
        .environment(\.scenePhase, .inactive)
        .environment(\.drawsGlassSnapshotBackdrop, true)
        .framedForTest(height: 844)

        assertSnapshot(of: view, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    /// Without the memory to derive the key, AutoFill sends the user to the app instead of asking for the password.
    @Test(arguments: [ColorScheme.light, .dark])
    func autofillOpenVault(colorScheme: ColorScheme) {
        let view = NavigationStack {
            AppLockOpenVaultView {}
        }
        .framedForTest(height: 844)

        assertSnapshot(of: view, colorScheme: colorScheme, named: "\(colorScheme)")
    }
}

// MARK: - Helpers

extension AppLockViewSnapshotTests {
    private func snapshotScenarios(
        view: some View,
        dynamicTypeSizes: [DynamicTypeSize] = [.medium, .xxLarge],
        testName: String = #function,
    ) {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = view
                    .environment(\.drawsGlassSnapshotBackdrop, true)
                    .dynamicTypeSize(dynamicTypeSize)
                    // A phone screen, as the lock screen fills one.
                    .framedForTest(height: 844)

                assertSnapshot(
                    of: snapshottingView,
                    colorScheme: colorScheme,
                    named: "\(colorScheme)_\(dynamicTypeSize)",
                    testName: testName,
                )
            }
        }
    }
}
