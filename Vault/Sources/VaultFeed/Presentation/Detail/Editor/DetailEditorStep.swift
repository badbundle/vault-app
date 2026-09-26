import Foundation

/// A part of an item's editor.
///
/// Every kind of item is edited in the same parts, in this order, leaving out any it doesn't have. What each part
/// holds depends on the kind of item.
public enum DetailEditorStep: Int, CaseIterable, Hashable, Comparable, Sendable {
    /// What the item holds: a code's key, a note's text, a recovery phrase's words.
    case content
    /// What the item is called: a code's site and account, a recovery phrase's title and description.
    case details
    /// How the item looks in the vault: its color and tags.
    case appearance
    /// Who can see the item and how it's protected.
    case security

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Edits that can say whether each of the editor's steps has everything it needs.
public protocol DetailEditorEditableState: EditableState {
    /// Whether everything `step` requires has been filled in validly, so the editor can move on from it.
    ///
    /// A step with nothing required is always complete.
    func isComplete(_ step: DetailEditorStep) -> Bool
}
