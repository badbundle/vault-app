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
