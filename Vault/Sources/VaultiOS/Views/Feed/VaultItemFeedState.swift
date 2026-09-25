import Foundation

/// User state of the vault feed.
@Observable
public final class VaultItemFeedState {
    var isEditing = false
    var isReordering = false
    /// Whether the feed bar is minimized to its compact capsules.
    var isBarCollapsed = false
    /// Whether the search field is open in the feed bar, in place of the
    /// search button. A non-empty query keeps it open regardless.
    var isSearchPresented = false

    /// Updated on every scroll frame, so it sits outside observation: only
    /// the collapse it requests should redraw the feed.
    @ObservationIgnored var barTracker = FeedBarCollapseTracker()

    public init() {}
}
