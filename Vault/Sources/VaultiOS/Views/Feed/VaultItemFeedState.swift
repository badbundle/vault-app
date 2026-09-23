import Foundation

/// User state of the vault feed.
@Observable
public final class VaultItemFeedState {
    var isEditing = false
    var isReordering = false
    /// Whether the feed bar is minimized to its compact capsule.
    var isBarCollapsed = false

    /// Updated on every scroll frame, so it sits outside observation: only
    /// the collapse it requests should redraw the feed.
    @ObservationIgnored var barTracker = FeedBarCollapseTracker()

    public init() {}
}
