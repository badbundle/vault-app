import Foundation
import SwiftUI
import Testing
@testable import VaultiOS

struct FeedBarCollapseTrackerTests {
    @Test
    func collapsesAfterScrollingDownPastThreshold() {
        var sut = makeSUT(phase: .interacting)

        let changes = scroll(&sut, through: [100, 120, 132])

        #expect(changes == [nil, nil, .collapse])
    }

    @Test
    func doesNotCollapseJustShortOfThreshold() {
        var sut = makeSUT(phase: .interacting)

        let changes = scroll(&sut, through: [100, 131])

        #expect(changes == [nil, nil])
    }

    @Test
    func expandsAfterScrollingUpPastThreshold() {
        var sut = makeSUT(phase: .interacting)

        let changes = scroll(&sut, through: [500, 490, 476])

        #expect(changes == [nil, nil, .expand])
    }

    @Test
    func smallReversalDoesNotExpand() {
        var sut = makeSUT(phase: .interacting)

        let changes = scroll(&sut, through: [100, 150, 140])

        #expect(changes == [nil, .collapse, nil])
    }

    @Test
    func reversingDirectionResetsTravel() {
        var sut = makeSUT(phase: .interacting)

        // 25 down, 5 up, 20 down: 40 in total, but only 20 since the reversal.
        let changes = scroll(&sut, through: [100, 125, 120, 140])

        #expect(changes == [nil, nil, nil, nil])
    }

    @Test
    func newGestureResetsTravel() {
        var sut = makeSUT(phase: .interacting)
        _ = scroll(&sut, through: [100, 120])

        sut.phaseChanged(to: .idle)
        sut.phaseChanged(to: .tracking)
        sut.phaseChanged(to: .interacting)
        let changes = scroll(&sut, through: [135])

        #expect(changes == [nil])
    }

    @Test(arguments: [ScrollPhase.idle, .animating, .interacting])
    func expandsWithinTopZoneInAnyPhase(phase: ScrollPhase) {
        var sut = makeSUT(phase: phase)

        let changes = scroll(&sut, through: [FeedBarCollapseTracker.topZone])

        #expect(changes == [.expand])
    }

    @Test
    func expandsWhenPulledDownPastTop() {
        var sut = makeSUT(phase: .interacting)

        let changes = scroll(&sut, through: [-40])

        #expect(changes == [.expand])
    }

    @Test(arguments: [CGFloat(0), -10])
    func expandsWhenContentFits(maxOffset: CGFloat) {
        var sut = makeSUT(phase: .interacting)

        let changes = scroll(&sut, through: [0], maxOffset: maxOffset)

        #expect(changes == [.expand])
    }

    @Test(arguments: [ScrollPhase.idle, .animating])
    func ignoresMovementThatIsNotTheUserScrolling(phase: ScrollPhase) {
        var sut = makeSUT(phase: phase)

        let changes = scroll(&sut, through: [100, 200, 50])

        #expect(changes == [nil, nil, nil])
    }

    @Test
    func ignoresTheFrameWhereScrollableExtentChanges() {
        var sut = makeSUT(phase: .interacting)

        let first = sut.scrolled(to: .init(offset: 100, maxOffset: 1000), canCollapse: true)
        let resized = sut.scrolled(to: .init(offset: 200, maxOffset: 900), canCollapse: true)
        let next = sut.scrolled(to: .init(offset: 232, maxOffset: 900), canCollapse: true)

        #expect(first == nil)
        #expect(resized == nil)
        #expect(next == .collapse)
    }

    /// Collapsing at the bottom shrinks the bar, so the feed's extent shrinks
    /// and the offset is pulled back in; none of that is scrolling up.
    @Test
    func bounceAndResizeAtBottomAfterCollapsingDoNotExpand() {
        var sut = makeSUT(phase: .decelerating)

        let collapse = scroll(&sut, through: [360, 400], maxOffset: 400)
        let bounce = scroll(&sut, through: [430, 400], maxOffset: 400)
        let resized = sut.scrolled(to: .init(offset: 400, maxOffset: 350), canCollapse: true)
        let settled = sut.scrolled(to: .init(offset: 350, maxOffset: 350), canCollapse: true)

        #expect(collapse == [nil, .collapse])
        #expect(bounce == [nil, nil])
        #expect(resized == nil)
        #expect(settled == nil)
    }

    @Test
    func neverCollapsesWithLittleToScroll() {
        var sut = makeSUT(phase: .interacting)

        let changes = scroll(&sut, through: [50, 100, 150], maxOffset: FeedBarCollapseTracker.minimumOverflow - 1)

        #expect(changes == [nil, nil, nil])
    }

    @Test
    func neverCollapsesWhenCollapsingIsDisallowed() {
        var sut = makeSUT(phase: .interacting)

        let down = scroll(&sut, through: [100, 200], canCollapse: false)
        let up = scroll(&sut, through: [150], canCollapse: false)

        #expect(down == [nil, nil])
        #expect(up == [.expand])
    }

    @Test
    func resetTravelForgetsProgressTowardsCollapsing() {
        var sut = makeSUT(phase: .interacting)
        _ = scroll(&sut, through: [100, 125])

        sut.resetTravel()
        let changes = scroll(&sut, through: [140])

        #expect(changes == [nil])
    }

    @Test
    func positionFromScrollGeometryMeasuresFromTheTopInset() {
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: -100),
            contentSize: CGSize(width: 390, height: 2000),
            contentInsets: EdgeInsets(top: 100, leading: 0, bottom: 50, trailing: 0),
            containerSize: CGSize(width: 390, height: 800),
        )

        let position = FeedScrollPosition(geometry)

        #expect(position == FeedScrollPosition(offset: 0, maxOffset: 1350))
    }
}

// MARK: - Helpers

extension FeedBarCollapseTrackerTests {
    private func makeSUT(phase: ScrollPhase) -> FeedBarCollapseTracker {
        var sut = FeedBarCollapseTracker()
        sut.phaseChanged(to: phase)
        return sut
    }

    private func scroll(
        _ sut: inout FeedBarCollapseTracker,
        through offsets: [CGFloat],
        maxOffset: CGFloat = 1000,
        canCollapse: Bool = true,
    ) -> [FeedBarCollapseTracker.Change?] {
        offsets.map { offset in
            sut.scrolled(to: .init(offset: offset, maxOffset: maxOffset), canCollapse: canCollapse)
        }
    }
}
