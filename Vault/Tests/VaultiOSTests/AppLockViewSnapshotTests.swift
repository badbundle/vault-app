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

    /// A screen whose safe area is wider on one side, as the iPhone Duo's unfolded is: the door is still in the middle
    /// of the screen, and the words under it are under it, inside the safe area.
    @Test
    func locked_onAScreenWithAnUnevenSafeArea() {
        snapshotScenarios(
            view: AppLockView(state: .init(step: .deviceAuthentication)) {}
                .safeAreaPadding(.leading, 96),
            dynamicTypeSizes: [.medium, .accessibility3],
        )
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
    func passwordEntry_onAScreenWithAnUnevenSafeArea() {
        snapshotScenarios(
            view: AppLockView(state: .init(step: .password)) {}
                .safeAreaPadding(.trailing, 96),
            dynamicTypeSizes: [.medium, .accessibility3],
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

    /// In AutoFill, at the attempt that could erase every vault: never why, only where to go.
    @Test
    func passwordNeedsTheApp() {
        snapshotScenarios(
            view: AppLockView(state: .init(step: .password, failure: .needsTheApp)) {},
            dynamicTypeSizes: [.medium],
        )
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
