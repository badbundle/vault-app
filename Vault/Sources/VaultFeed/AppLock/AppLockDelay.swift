import Foundation

/// How long the app can be in the background before it locks.
public enum AppLockDelay: Int, CaseIterable, Identifiable, Comparable, Sendable {
    // Raw values are the delay in seconds, as stored: don't change them.
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    /// The default: the app locks as soon as it goes to the background.
    public static let `default`: AppLockDelay = .immediately

    public var id: Self {
        self
    }

    public var duration: Duration {
        .seconds(rawValue)
    }

    public var localizedName: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 Minute"
        case .fiveMinutes: "After 5 Minutes"
        case .fifteenMinutes: "After 15 Minutes"
        }
    }

    public static func < (lhs: AppLockDelay, rhs: AppLockDelay) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Time for the app lock's delays, which only ever moves forward until the device restarts.
///
/// Changing the device's date and time doesn't move it, so it can't be wound back to stretch the delay before the app
/// locks, or forward to cut short the wait after wrong password attempts. It restarts with the device. The delay
/// before locking is only compared within one run of the app, and a new run always starts locked.
/// `AppLockPasswordAttemptCounter` compares it across runs, and starts its delay again when it finds time has gone
/// back.
public protocol AppLockClock: Sendable {
    var now: ContinuousClock.Instant { get }
}

/// Counts time while the device sleeps too, so a phone left asleep in a pocket still locks the app.
extension ContinuousClock: AppLockClock {}
