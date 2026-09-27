import CoreSpotlight
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct SpotlightCodeIndexerTests {
    /// An index left from before, perhaps before App Lock was turned on, is emptied at launch.
    @Test
    func update_first_replacesTheIndexEvenWithNothing() async {
        let index = SpotlightCodeIndexMock()
        let sut = SpotlightCodeIndexer(index: index) { [] }

        await sut.update().value

        #expect(index.replaceArgValues == [[]])
    }

    @Test
    func update_withTheSameCodes_leavesTheIndexAlone() async {
        let index = SpotlightCodeIndexMock()
        let codes = [anySpotlightCode(name: "GitHub")]
        let sut = SpotlightCodeIndexer(index: index) { codes }

        await sut.update().value
        await sut.update().value

        #expect(index.replaceArgValues == [codes])
    }

    @Test
    func update_afterTheCodesChange_replacesTheIndex() async {
        let index = SpotlightCodeIndexMock()
        let github = anySpotlightCode(name: "GitHub")
        let google = anySpotlightCode(name: "Google")
        let codes = Codes([github])
        let sut = SpotlightCodeIndexer(index: index) { codes.value }
        await sut.update().value

        codes.value.append(google)
        await sut.update().value

        #expect(index.replaceArgValues == [[github], [github, google]])
    }

    /// Turning App Lock on while a fill is underway still leaves the index empty.
    @Test
    func update_runsInOrder_soTheLastUpdateWins() async {
        let index = SpotlightCodeIndexMock()
        let codes = Codes([anySpotlightCode(name: "GitHub")])
        let sut = SpotlightCodeIndexer(index: index) { codes.value }

        let first = sut.update()
        codes.value = []
        let second = sut.update()
        await first.value
        await second.value

        #expect(index.replaceArgValues.last == [])
    }

    @Test
    func update_afterReplacingFailed_triesAgain() async {
        let index = SpotlightCodeIndexMock()
        index.replaceHandler = { _ in throw TestError() }
        let codes = [anySpotlightCode(name: "GitHub")]
        let sut = SpotlightCodeIndexer(index: index) { codes }
        await sut.update().value

        index.replaceHandler = { _ in }
        await sut.update().value

        #expect(index.replaceCallCount == 2)
    }

    /// Nothing to go on, so the index stays as it is until the next change.
    @Test
    func update_whenTheVaultCantBeRead_leavesTheIndexAlone() async {
        let index = SpotlightCodeIndexMock()
        let sut = SpotlightCodeIndexer(index: index) { throw TestError() }

        await sut.update().value

        #expect(index.replaceCallCount == 0)
    }

    // MARK: - Opening a result

    @Test
    func spotlightItemID_isTheChosenItem() {
        let id = UUID()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: id.uuidString]

        #expect(activity.spotlightItemID == Identifier(id: id))
    }

    @Test
    func spotlightItemID_isNilForAnyOtherActivity() {
        let activity = NSUserActivity(activityType: "vault.other")
        activity.userInfo = [CSSearchableItemActivityIdentifier: UUID().uuidString]

        #expect(activity.spotlightItemID == nil)
    }
}

// MARK: - Helpers

extension SpotlightCodeIndexerTests {
    /// The codes the vault has, which a test changes between updates.
    @MainActor
    private final class Codes {
        var value: [SpotlightCode]

        init(_ value: [SpotlightCode]) {
            self.value = value
        }
    }

    private func anySpotlightCode(name: String) -> SpotlightCode {
        SpotlightCode(id: .new(), name: name)
    }
}
