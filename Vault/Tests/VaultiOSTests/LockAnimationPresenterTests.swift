import Foundation
import Testing
import VaultAppIcon
@testable import VaultiOS

@MainActor
struct LockAnimationPresenterTests {
    @Test
    func play_setsCurrentTransition() {
        let sut = LockAnimationPresenter()

        sut.play(.lock)

        #expect(sut.current?.transition == .lock)
    }

    @Test
    func playAgain_replacesPlaybackWithNewID() throws {
        let sut = LockAnimationPresenter()
        sut.play(.lock)
        let first = try #require(sut.current)

        sut.play(.lock)
        let second = try #require(sut.current)

        #expect(first.id != second.id)
        #expect(second.transition == .lock)
    }

    @Test
    func finish_matchingID_clearsCurrent() throws {
        let sut = LockAnimationPresenter()
        sut.play(.unlock)
        let playback = try #require(sut.current)

        sut.finish(playback.id)

        #expect(sut.current == nil)
    }

    @Test
    func finish_staleID_keepsCurrent() throws {
        let sut = LockAnimationPresenter()
        sut.play(.lock)
        let stale = try #require(sut.current)
        sut.play(.unlock)

        sut.finish(stale.id)

        #expect(sut.current?.transition == .unlock)
    }
}
