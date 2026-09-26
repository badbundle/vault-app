import Foundation
import Synchronization
import VaultFeed

/// Time that moves only when the test says so.
final class FakeAppLockClock: AppLockClock {
    private let current = Mutex(ContinuousClock.now)

    var now: ContinuousClock.Instant {
        current.withLock(\.self)
    }

    func advance(by duration: Duration) {
        current.withLock { $0 = $0.advanced(by: duration) }
    }

    /// Moves time back, as it does when the device restarts.
    func goBack(by duration: Duration) {
        advance(by: .zero - duration)
    }
}
