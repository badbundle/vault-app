import Foundation

/// Whether the app is locked, and if it is, how far the user has got with unlocking it.
public enum AppLockState: Equatable, Sendable {
    /// The vault is showing: the app lock is off, or the user has unlocked the app.
    case unlocked
    /// The vault is hidden behind the lock screen until the user has passed every step of unlocking.
    case locked(AppLockedState)
}

/// What the lock screen shows: the step of unlocking the user is on, and how their last try at it went.
public struct AppLockedState: Equatable, Sendable {
    public var step: AppUnlockStep
    /// Whether the step is underway, such as the Face ID prompt being up.
    public var isInProgress: Bool
    /// Why the last try at `step` didn't get the user past it, if it didn't.
    public var failure: AppUnlockFailure?

    public init(step: AppUnlockStep, isInProgress: Bool = false, failure: AppUnlockFailure? = nil) {
        self.step = step
        self.isInProgress = isInProgress
        self.failure = failure
    }
}

/// One thing the user does to unlock the app. Unlocking takes every step, in order.
///
/// Device authentication is the only step for now. An app lock password would be a second step after it, which the
/// lock screen asks for once the first is passed.
public enum AppUnlockStep: Equatable, Sendable {
    /// Face ID, Touch ID or the device passcode.
    case deviceAuthentication

    /// Whether the app starts this step by itself as soon as it's in the foreground, rather than waiting for the user.
    var startsAutomatically: Bool {
        switch self {
        case .deviceAuthentication: true
        }
    }
}

/// Why a try at an unlock step didn't get the user past it.
public enum AppUnlockFailure: Equatable, Sendable {
    /// The prompt went away without an answer: the user cancelled it, or the system did because the app left the
    /// foreground.
    case cancelled
    /// The user didn't pass, such as Face ID not recognizing them.
    case failed
    /// The device can't authenticate anyone, because it has no passcode.
    case unavailable
}

/// Where a scene of the app is in its lifecycle: SwiftUI's `ScenePhase`, which this module can't use.
public enum AppScenePhase: Equatable, Sendable {
    /// In the foreground and interactive.
    case active
    /// In the foreground but not interactive, such as under Control Center, the app switcher or a Face ID prompt.
    case inactive
    /// Not on screen.
    case background
}
