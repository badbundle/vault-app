import Foundation
import SwiftUI
import Synchronization
import TestHelpers
import Testing
import UIKit
import VaultFeed
@testable import VaultiOS

/// The lock screen while the password has to wait, after wrong passwords: the field and Unlock come back once the
/// wait's over, by the app lock's clock.
@MainActor
struct AppLockViewCountdownTests {
    @Test
    func passwordWait_endsWhenTheClockPassesIt() async throws {
        let clock = TestClock()
        let view = AppLockView(
            state: .init(
                step: .password,
                failure: .wrongPassword,
                passwordRetryAt: clock.now.advanced(by: .seconds(60)),
            ),
            unlock: {},
            clock: clock,
        )
        let field = try host(view)
        #expect(!field.isEnabled)

        clock.advance(by: .seconds(59))
        // The countdown checks the clock every second.
        try await Task.sleep(for: .milliseconds(1500))
        #expect(!field.isEnabled)

        clock.advance(by: .seconds(1))
        try await waitUntil { field.isEnabled }
    }
}

// MARK: - Helpers

extension AppLockViewCountdownTests {
    /// Time that moves only when the test says so.
    final class TestClock: AppLockClock {
        private let current = Mutex(ContinuousClock.now)

        var now: ContinuousClock.Instant {
            current.withLock(\.self)
        }

        func advance(by duration: Duration) {
            current.withLock { $0 = $0.advanced(by: duration) }
        }
    }

    /// Hosts the lock screen in a window and returns its password field. The test runner has no scene to put one in,
    /// so this uses the window initializer that doesn't take a scene, deprecated as it is.
    @diagnose(DeprecatedDeclaration, as: ignored)
    private func host(_ view: AppLockView) throws -> UITextField {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        Self.windows.append(window)
        return try #require(textFields(in: controller.view).first)
    }

    /// Windows kept up for the rest of the run, as taking one down while SwiftUI is still updating it can crash.
    private static var windows = [UIWindow]()

    private func textFields(in view: UIView) -> [UITextField] {
        let own = (view as? UITextField).map { [$0] } ?? []
        return own + view.subviews.flatMap(textFields(in:))
    }

    /// Waits for SwiftUI to catch up, up to a few seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
