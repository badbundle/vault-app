import Foundation
import VaultAppIcon

/// Asks for the full-screen lock animation to play.
///
/// Feedback only. It is driven solely by the user's own explicit lock or unlock
/// of the item they are looking at, whose lock state that screen already shows
/// openly. It records nothing, and nothing else (killphrases, search passphrases,
/// visibility, decryption) may drive it. See `MANIFESTO.md`.
@MainActor
@Observable
final class LockAnimationPresenter {
    /// One request to play. A fresh `id` per request means playing the same
    /// transition twice in a row restarts the animation.
    struct Playback: Identifiable, Equatable, Sendable {
        let id: UUID
        let transition: VaultLockTransition
    }

    private(set) var current: Playback?

    init() {}

    func play(_ transition: VaultLockTransition) {
        current = Playback(id: UUID(), transition: transition)
    }

    /// Ends the playback with `id`. Ignored when a newer playback has replaced it.
    func finish(_ id: Playback.ID) {
        guard current?.id == id else { return }
        current = nil
    }
}
