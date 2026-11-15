import Foundation
import Testing
import VaultSettings

@MainActor
struct RatingRequestPolicyTests {
    @Test
    func shouldAsk_asksOnceEachLaunch() {
        let sut = RatingRequestPolicy(isEnabled: true)

        #expect(sut.shouldAsk())
        #expect(!sut.shouldAsk())
        #expect(!sut.shouldAsk())
    }

    @Test
    func shouldAsk_whenDisabled_neverAsks() {
        let sut = RatingRequestPolicy(isEnabled: false)

        #expect(!sut.shouldAsk())
        #expect(!sut.shouldAsk())
    }

    /// A policy made afresh, as at the next launch, asks again: nothing about the last time was saved anywhere (G107).
    @Test
    func shouldAsk_atTheNextLaunch_asksAgainAsNothingWasSaved() {
        let lastLaunch = RatingRequestPolicy(isEnabled: true)
        #expect(lastLaunch.shouldAsk())

        let sut = RatingRequestPolicy(isEnabled: true)

        #expect(sut.shouldAsk())
    }

    @Test
    func writeReviewURL_isVaultsAppStorePageAtWriteAReview() {
        let url = VaultAppStore.writeReviewURL

        #expect(url.host() == "apps.apple.com")
        #expect(url.path() == "/app/id6738931366")
        #expect(url.query() == "action=write-review")
    }
}
