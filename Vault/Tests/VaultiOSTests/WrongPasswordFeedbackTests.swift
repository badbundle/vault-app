import Foundation
import SwiftUI
import Testing
@testable import VaultiOS

/// The shake a password field gives a wrong password.
@MainActor
struct WrongPasswordFeedbackTests {
    /// The field ends exactly where it started, in line with what's around it, however the shake ends.
    @Test
    func shake_endsWhereItStarted() {
        let timeline = KeyframeTimeline(initialValue: 0.0) {
            KeyframeTrack {
                WrongPasswordFeedback.shake
            }
        }

        #expect(timeline.value(progress: 1) == 0)
        #expect(timeline.value(time: timeline.duration + 1) == 0)
        #expect(timeline.value(progress: 0.2) != 0)
    }
}
