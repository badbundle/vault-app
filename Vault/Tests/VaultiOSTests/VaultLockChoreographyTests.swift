import Foundation
import SwiftUI
import Testing
@testable import VaultAppIcon

struct VaultLockChoreographyTests {
    private static let transitions: [VaultLockTransition] = [.lock, .unlock, .decrypt, .decryptionFailed]

    @Test(arguments: transitions)
    func keyframes_finishBeforeTotalDuration(transition: VaultLockTransition) {
        let choreography = VaultLockChoreography(transition: transition, reduceMotion: false)

        #expect(.seconds(timeline(for: transition).duration) <= choreography.totalDuration)
    }

    @Test(arguments: transitions)
    func keyframes_endOnFinalGlyph(transition: VaultLockTransition) {
        let end = timeline(for: transition).value(progress: 1)
        let final = LockGlyphKeyframes.final(for: transition)

        // The wheel's four arms look the same every quarter turn, and a spring may
        // be a few degrees short of settling when the keyframes run out.
        let quarterTurnOffset = abs(end.wheelRotation.truncatingRemainder(dividingBy: 90))
        #expect(min(quarterTurnOffset, 90 - quarterTurnOffset) < 5)
        #expect(abs(end.doorOpening - final.doorOpening) < 0.05)
        #expect(abs(end.doorScale - final.doorScale) < 0.01)
        #expect(abs(end.doorShake - final.doorShake) < 0.01)
    }

    @Test(arguments: transitions, [false, true])
    func clickDelay_isBeforeTotalDuration(transition: VaultLockTransition, reduceMotion: Bool) {
        let choreography = VaultLockChoreography(transition: transition, reduceMotion: reduceMotion)

        #expect(choreography.clickDelay < choreography.totalDuration)
    }

    @Test
    func decryptedDoor_opensWiderThanUnlock() {
        #expect(VaultLockChoreography.decryptedDoor > VaultLockChoreography.openedDoor)
    }
}

// MARK: - Helpers

extension VaultLockChoreographyTests {
    private func timeline(for transition: VaultLockTransition) -> KeyframeTimeline<LockGlyphKeyframes> {
        let initial = LockGlyphKeyframes.initial(for: transition)
        return switch transition {
        case .lock: KeyframeTimeline(initialValue: initial) { LockGlyphKeyframes.lock }
        case .unlock: KeyframeTimeline(initialValue: initial) { LockGlyphKeyframes.unlock }
        case .decrypt: KeyframeTimeline(initialValue: initial) { LockGlyphKeyframes.decrypt }
        case .decryptionFailed: KeyframeTimeline(initialValue: initial) { LockGlyphKeyframes.decryptionFailed }
        }
    }
}
