import AppKit
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultMac

@MainActor
struct VaultMacLockViewSnapshotTests {
    @Test(arguments: MacAppearance.allCases)
    func deviceAuthentication(appearance: MacAppearance) {
        assertSnapshot(
            of: lockView(state: .init(step: .deviceAuthentication)),
            as: .macWindow(width: 720, height: 480, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    @Test(arguments: MacAppearance.allCases)
    func password(appearance: MacAppearance) {
        assertSnapshot(
            of: lockView(state: .init(step: .password)),
            as: .macWindow(width: 720, height: 480, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    @Test
    func wrongPassword_waiting() {
        let clock = FakeAppLockClock()
        assertSnapshot(
            of: lockView(
                state: .init(
                    step: .password,
                    failure: .wrongPassword,
                    passwordRetryAt: clock.now.advanced(by: .seconds(5 * 60)),
                ),
                clock: clock,
            ),
            as: .macWindow(width: 720, height: 480),
        )
    }

    @Test
    func unavailable() {
        assertSnapshot(
            of: lockView(state: .init(step: .deviceAuthentication, failure: .unavailable)),
            as: .macWindow(width: 720, height: 480),
        )
    }

    @Test(arguments: MacAppearance.allCases)
    func firstLaunch(appearance: MacAppearance) throws {
        let appLock = try AppLockService(
            settings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            authenticationService: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            passwordService: FakeAppLockPasswordService(),
            purgeSensitiveData: {},
        )
        assertSnapshot(
            of: VaultMacFirstLaunchView(appLock: appLock, canAuthenticate: true),
            as: .macWindow(width: 720, height: 640, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    private func lockView(state: AppLockedState, clock: any AppLockClock = ContinuousClock()) -> some View {
        VaultMacLockView(state: state, unlock: {}, unlockWithPassword: { _ in }, clock: clock)
    }
}

/// The Mac's light and dark appearances, for snapshots of both.
enum MacAppearance: String, CaseIterable, Sendable {
    case light
    case dark

    var name: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
