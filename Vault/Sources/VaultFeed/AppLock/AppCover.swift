import Foundation

/// What hides the whole vault from view when it isn't locked, if anything.
///
/// Drawn in the app lock's window, so it covers sheets too. The lock screen, when the app is locked, takes precedence
/// over both: it shows nothing of the vault either.
public enum AppCover: Equatable, Sendable {
    /// The app lock is on and the app isn't in the foreground: for the app switcher, Control Center and the like.
    case privacy
    /// The screen is being recorded, mirrored or shared.
    case screenCapture

    /// The cover a scene needs, if any.
    ///
    /// - Parameters:
    ///   - isPrivacyCoverRequired: From `AppLockService.requiresPrivacyCover(in:)`.
    ///   - hidesVaultWhileScreenCaptured: The user's setting. Independent of the app lock.
    ///   - isScreenCaptured: Whether the scene is being recorded, mirrored or shared right now.
    public static func required(
        isPrivacyCoverRequired: Bool,
        hidesVaultWhileScreenCaptured: Bool,
        isScreenCaptured: Bool,
    ) -> AppCover? {
        // The capture cover explains itself, so it wins: going inactive mid-recording (Control Center, say) doesn't
        // swap it for the plainer privacy cover and back.
        if hidesVaultWhileScreenCaptured, isScreenCaptured {
            .screenCapture
        } else if isPrivacyCoverRequired {
            .privacy
        } else {
            nil
        }
    }
}
