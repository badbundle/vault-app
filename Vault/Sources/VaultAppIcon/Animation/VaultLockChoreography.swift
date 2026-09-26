import Foundation

/// The timing of one run of the lock animation.
///
/// Shared between the keyframes in `VaultLockAnimationView` and whoever shows it,
/// so a haptic can land exactly when the mechanism seats and what follows can wait
/// until the spring has settled.
public struct VaultLockChoreography: Sendable {
    public var transition: VaultLockTransition
    public var reduceMotion: Bool

    public init(transition: VaultLockTransition, reduceMotion: Bool) {
        self.transition = transition
        self.reduceMotion = reduceMotion
    }

    /// How far the door stands open when unlocked, as a fraction of
    /// `VaultIconMetrics.doorOpenAngle`.
    public static let openedDoor: Double = 0.32

    /// How far the door stands open once an item is decrypted: wide, where an
    /// unlock only opens it a crack.
    public static let decryptedDoor: Double = 1.5

    /// When the wheel seats and the bolts go home (or, for a failed decryption,
    /// when the wheel first catches): the moment for a haptic.
    public var clickDelay: Duration {
        switch (reduceMotion, transition) {
        case (true, _): .milliseconds(150)
        case (false, .lock): .milliseconds(740)
        case (false, .unlock): .milliseconds(640)
        case (false, .decrypt): .milliseconds(680)
        case (false, .decryptionFailed): .milliseconds(60)
        }
    }

    /// When the animation is over and the presentation can go.
    public var totalDuration: Duration {
        switch (reduceMotion, transition) {
        case (true, _): .milliseconds(700)
        case (false, .lock), (false, .unlock): .milliseconds(1250)
        case (false, .decrypt): .milliseconds(1300)
        case (false, .decryptionFailed): .milliseconds(600)
        }
    }
}

/// The animated properties of the glyph: one keyframe value.
struct LockGlyphKeyframes {
    /// Degrees. Thanks to the wheel's four-fold symmetry, any multiple of 90 lands
    /// on the same silhouette as 0, so a run always ends where a fresh glyph starts.
    var wheelRotation: Double
    var doorOpening: Double
    var doorScale: Double
    /// Sideways offset of the whole door, as a fraction of the glyph's width.
    var doorShake: Double = 0

    static func initial(for transition: VaultLockTransition) -> LockGlyphKeyframes {
        switch transition {
        case .lock:
            LockGlyphKeyframes(wheelRotation: 0, doorOpening: VaultLockChoreography.openedDoor, doorScale: 1)
        case .unlock, .decrypt, .decryptionFailed:
            LockGlyphKeyframes(wheelRotation: 0, doorOpening: 0, doorScale: 1)
        }
    }

    static func final(for transition: VaultLockTransition) -> LockGlyphKeyframes {
        switch transition {
        case .lock, .decryptionFailed:
            LockGlyphKeyframes(wheelRotation: 0, doorOpening: 0, doorScale: 1)
        case .unlock:
            LockGlyphKeyframes(wheelRotation: 0, doorOpening: VaultLockChoreography.openedDoor, doorScale: 1)
        case .decrypt:
            LockGlyphKeyframes(wheelRotation: 0, doorOpening: VaultLockChoreography.decryptedDoor, doorScale: 1)
        }
    }
}
