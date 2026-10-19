import Foundation
import SwiftUI

/// What the feed shows while it has no items.
///
/// With `onAdd`, it offers each kind of item to add, in the order of the new-item sheet, so the first thing a new
/// person sees points at recovery phrases and private keys. Choosing one starts making that item. Without it, as in
/// AutoFill, which can't add items, or while a search or filter is hiding items, it only says there are none.
struct EmptyFeedView: View {
    var onAdd: ((CreatingItem) -> Void)?

    var body: some View {
        if let onAdd {
            ContentUnavailableView {
                title
            } description: {
                Text("Add an item to get started.")
            } actions: {
                ForEach(CreatingItem.addOrder, id: \.self) { item in
                    Button {
                        onAdd(item)
                    } label: {
                        Label("Add \(item.title)", systemImage: item.systemImage)
                    }
                }
            }
        } else {
            ContentUnavailableView {
                title
            }
        }
    }

    private var title: some View {
        Label(localized(key: "codeFeed.noCodes.title"), systemImage: "key.horizontal")
    }
}

#Preview("Offers to add") {
    EmptyFeedView { _ in }
}

#Preview("Nothing to offer") {
    EmptyFeedView()
}
