import Foundation
import Testing
@testable import VaultiOS

struct CreateItemFlowTests {
    @Test
    func init_startsOnChoosingTheItemType() {
        let sut = CreateItemFlow()

        #expect(sut.creatingItem == nil)
    }

    @Test(arguments: [CreatingItem.otpCode, .secureNote, .recoveryPhrase])
    func choose_goesForwardToMakingThatItem(item: CreatingItem) {
        var sut = CreateItemFlow()

        sut.choose(item)

        #expect(sut.creatingItem == item)
        #expect(sut.direction == .forward)
    }

    @Test
    func choose_whileMakingAnItemKeepsThatItem() {
        var sut = CreateItemFlow()
        sut.choose(.secureNote)

        sut.choose(.otpCode)

        #expect(sut.creatingItem == .secureNote)
        #expect(sut.direction == .forward)
    }

    @Test
    func goBackToItemTypes_fromAnItemGoesBackToTheChoice() {
        var sut = CreateItemFlow()
        sut.choose(.secureNote)

        sut.goBackToItemTypes()

        #expect(sut.creatingItem == nil)
        #expect(sut.direction == .backward)
    }

    @Test
    func goBackToItemTypes_whileChoosingDoesNothing() {
        var sut = CreateItemFlow()

        sut.goBackToItemTypes()

        #expect(sut == CreateItemFlow())
    }

    @Test
    func choose_afterGoingBackStartsTheNewChoiceForwards() {
        var sut = CreateItemFlow()
        sut.choose(.otpCode)
        sut.goBackToItemTypes()

        sut.choose(.recoveryPhrase)

        #expect(sut.creatingItem == .recoveryPhrase)
        #expect(sut.direction == .forward)
    }
}
