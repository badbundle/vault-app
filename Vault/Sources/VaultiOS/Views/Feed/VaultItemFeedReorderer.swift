import Foundation
import FoundationExtensions
import VaultFeed

struct VaultItemFeedReorderer {
    private let state: [Identifier<VaultItem>]
    init(state: [Identifier<VaultItem>]) {
        self.state = state
    }

    enum ReorderResult: Equatable {
        case noMove
        case move(Move)

        struct Move: Equatable {
            var fromIndex: Int
            var toIndex: Int
            var reorderingPosition: VaultReorderingPosition
        }
    }

    /// Reorder a given vault item to a new position in place of an existing vault item.
    func reorder(item: Identifier<VaultItem>, to newPosition: Identifier<VaultItem>) -> ReorderResult {
        guard item != newPosition else { return .noMove }
        guard let from = state.firstIndex(of: item),
              var to = state.firstIndex(of: newPosition),
              from != to
        else {
            return .noMove
        }
        // If we are moving this item further down the list than we started, advance it by 1 more position.
        if to > from {
            to += 1
        }
        let targetPosition: VaultReorderingPosition = if to == 0 {
            .start
        } else {
            .after(state[to - 1])
        }
        return .move(.init(fromIndex: from, toIndex: to, reorderingPosition: targetPosition))
    }
}
