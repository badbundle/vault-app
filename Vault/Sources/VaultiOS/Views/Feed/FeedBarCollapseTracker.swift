import SwiftUI

/// Where the feed's vertical scroll view sits, reduced to what the feed bar
/// needs to decide whether to collapse.
struct FeedScrollPosition: Equatable {
    /// Distance scrolled from the top of the content: zero at rest at the
    /// top, negative while pulled down past it.
    var offset: CGFloat
    /// The furthest `offset` can reach at rest; zero or less when the content
    /// fits without scrolling.
    var maxOffset: CGFloat

    init(offset: CGFloat, maxOffset: CGFloat) {
        self.offset = offset
        self.maxOffset = maxOffset
    }

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.y + geometry.contentInsets.top
        maxOffset = geometry.contentSize.height
            + geometry.contentInsets.top
            + geometry.contentInsets.bottom
            - geometry.containerSize.height
    }

    /// The offset with rubber-banding at either end removed.
    fileprivate var clampedOffset: CGFloat {
        min(max(offset, 0), max(maxOffset, 0))
    }
}

/// Decides when the feed bar should collapse as the feed scrolls, the way the
/// system minimizes a tab bar: collapse on a deliberate scroll down, expand on
/// a scroll back up or on returning to the top.
///
/// This only requests changes; the collapsed state itself lives with the view
/// so it can be set directly, for example in snapshot tests.
struct FeedBarCollapseTracker {
    enum Change: Equatable {
        case collapse
        case expand
    }

    /// Continuous downward travel needed before the bar collapses.
    static let collapseDistance: CGFloat = 32
    /// Continuous upward travel needed before the bar expands again.
    static let expandDistance: CGFloat = 24
    /// Within this distance of the top the bar is always expanded.
    static let topZone: CGFloat = 24
    /// Content must overflow by at least this much before the bar collapses.
    ///
    /// Collapsing shrinks the bar, which shrinks how far the feed can scroll;
    /// this must exceed that change plus `topZone`, or collapsing at the
    /// bottom of a short feed could land in the top zone and expand again.
    static let minimumOverflow: CGFloat = 160

    private var lastPosition: FeedScrollPosition?
    private var isUserScrolling = false
    /// Until the person scrolls, the bar can only have been collapsed from
    /// outside (in a snapshot test, say), so the tracker has nothing to undo.
    private var hasUserScrolled = false
    /// Signed distance travelled in the current direction; positive is down.
    private var travel: CGFloat = 0

    mutating func phaseChanged(to phase: ScrollPhase) {
        let wasUserScrolling = isUserScrolling
        switch phase {
        case .tracking, .interacting, .decelerating:
            isUserScrolling = true
            hasUserScrolled = true
        case .idle, .animating:
            // Programmatic scrolls (including a tap on the status bar) and
            // layout changes are not the person scrolling.
            isUserScrolling = false
        }
        // Each gesture decides for itself; travel left over from an earlier
        // one should not tip this one over a threshold.
        if phase == .tracking || (isUserScrolling && !wasUserScrolling) {
            travel = 0
        }
    }

    mutating func scrolled(to position: FeedScrollPosition, canCollapse: Bool) -> Change? {
        let previous = lastPosition
        lastPosition = position
        guard hasUserScrolled else { return nil }

        // Near the top, or with nothing to scroll, the bar is always shown.
        // These can only expand, so they apply whatever caused the change.
        if position.maxOffset <= 0 || position.clampedOffset <= Self.topZone {
            travel = 0
            return .expand
        }

        // A change in scrollable extent means a reload, the keyboard, or the
        // bar itself resizing: the offset jump that comes with it isn't travel.
        guard let previous, abs(position.maxOffset - previous.maxOffset) <= 0.5 else {
            return nil
        }
        guard isUserScrolling else { return nil }

        let delta = position.clampedOffset - previous.clampedOffset
        guard delta != 0 else { return nil }
        if travel != 0, (delta > 0) != (travel > 0) {
            travel = 0
        }
        travel += delta

        if travel >= Self.collapseDistance, canCollapse, position.maxOffset >= Self.minimumOverflow {
            return .collapse
        }
        if travel <= -Self.expandDistance {
            return .expand
        }
        return nil
    }

    /// Forgets any travel so far, for when the bar is expanded directly.
    mutating func resetTravel() {
        travel = 0
    }
}
