import Foundation
import VaultFeed

/// Where the new-item sheet is: choosing what kind of item to make, or making it.
///
/// The choice is the sheet's first step. Choosing a kind goes on to that kind's editor, which starts on its own
/// first step, and Back from there comes back to the choice.
struct CreateItemFlow: Equatable {
    /// The kind of item being made, or `nil` while it's being chosen.
    private(set) var creatingItem: CreatingItem?
    /// Which way the sheet last moved, so the change can slide the right way.
    private(set) var direction: DetailEditorFlow.Direction = .forward

    init(creatingItem: CreatingItem? = nil) {
        self.creatingItem = creatingItem
    }

    /// Goes on to making `item`, while the kind of item is being chosen.
    mutating func choose(_ item: CreatingItem) {
        // A second tap as the choice slides away doesn't swap the item being made for another.
        guard creatingItem == nil else { return }
        direction = .forward
        creatingItem = item
    }

    /// Goes back to choosing the kind of item, leaving the one being made.
    mutating func goBackToItemTypes() {
        guard creatingItem != nil else { return }
        direction = .backward
        creatingItem = nil
    }
}
