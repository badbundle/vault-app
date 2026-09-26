import Foundation
import SwiftUI

/// How the App Lock Password's screens talk about the wait after wrong passwords.
///
/// They only ever say how long to wait, never how many attempts have been made or are left.
enum AppLockPasswordWait {
    /// How long is left to wait at `now`, or `nil` if the password can be tried.
    static func remaining(
        until retryAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant = .now,
    ) -> Duration? {
        guard let retryAt, now < retryAt else { return nil }
        return now.duration(to: retryAt)
    }

    /// "Try again in 5 minutes": in whole minutes rounded up, or hours from an hour.
    static func tryAgainMessage(after remaining: Duration) -> String {
        let minutes = (Double(remaining.components.seconds) / 60).rounded(.up)
        let wait: String = if minutes >= 60 {
            Duration.seconds((minutes / 60).rounded(.up) * 3600).formatted(.units(allowed: [.hours], width: .wide))
        } else {
            Duration.seconds(max(minutes, 1) * 60).formatted(.units(allowed: [.minutes], width: .wide))
        }
        return "Try again in \(wait)."
    }
}

extension View {
    /// Shakes the view, as a password field does when the password was wrong, each time `trigger` changes. With
    /// Reduce Motion, it fades out and back instead. The error haptic plays either way.
    func wrongPasswordFeedback(trigger: Int) -> some View {
        modifier(WrongPasswordFeedback(trigger: trigger))
    }
}

private struct WrongPasswordFeedback: ViewModifier {
    var trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, opacity in
                    content.opacity(opacity)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0.3, duration: 0.15)
                        LinearKeyframe(1, duration: 0.25)
                    }
                }
            } else {
                content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, offset in
                    content.offset(x: offset)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-12, duration: 0.06)
                        LinearKeyframe(10, duration: 0.08)
                        LinearKeyframe(-7, duration: 0.08)
                        LinearKeyframe(4, duration: 0.07)
                        SpringKeyframe(0, duration: 0.2)
                    }
                }
            }
        }
        .sensoryFeedback(.error, trigger: trigger)
    }
}
