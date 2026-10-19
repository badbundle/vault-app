import Foundation
import Testing
@testable import VaultiOS

struct CreaseTests {
    @Test
    func partlyFoldedWindow_wideHasCreaseDownTheMiddle() {
        let crease = Crease(partlyFoldedWindowOf: CGRect(x: 0, y: 0, width: 951, height: 669))

        #expect(crease == Crease(axis: .vertical, position: 475.5))
    }

    @Test
    func partlyFoldedWindow_tallHasCreaseAcrossTheMiddle() {
        let crease = Crease(partlyFoldedWindowOf: CGRect(x: 0, y: 0, width: 669, height: 951))

        #expect(crease == Crease(axis: .horizontal, position: 475.5))
    }

    @Test
    func partlyFoldedWindow_isInTheMiddleOfWhereTheWindowIs() {
        let crease = Crease(partlyFoldedWindowOf: CGRect(x: 100, y: 50, width: 951, height: 669))

        #expect(crease == Crease(axis: .vertical, position: 575.5))
    }

    @Test
    func split_givesTheRoomEachSideOfTheBand() {
        let crease = Crease(axis: .vertical, position: 500)

        let split = crease.split(CGRect(x: 100, y: 0, width: 800, height: 300))

        #expect(split == CreaseSplit(axis: .vertical, before: 388, after: 388))
        #expect(split?.afterStart == 412)
    }

    @Test
    func split_measuresAHorizontalCreaseDown() {
        let crease = Crease(axis: .horizontal, position: 400)

        let split = crease.split(CGRect(x: 0, y: 50, width: 300, height: 700))

        #expect(split == CreaseSplit(axis: .horizontal, before: 338, after: 338))
    }

    @Test(arguments: [
        // Wholly before the crease, or after it.
        CGRect(x: 0, y: 0, width: 400, height: 300),
        CGRect(x: 600, y: 0, width: 300, height: 300),
        // Starting at the crease, as the content beside a sidebar does.
        CGRect(x: 500, y: 0, width: 500, height: 300),
        // Ending inside the band.
        CGRect(x: 0, y: 0, width: 505, height: 300),
    ])
    func split_isNilWhereTheBandDoesNotCrossTheView(frame: CGRect) {
        let crease = Crease(axis: .vertical, position: 500)

        #expect(crease.split(frame) == nil)
    }
}
