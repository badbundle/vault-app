import Foundation
import SwiftUI
import UIKit

/// Text the user can select and copy, where copying goes through Vault's clipboard rather than the system's.
///
/// The system's copy would put the text on the clipboard without Clear Clipboard's expiry, offer it to the user's
/// other devices over Universal Clipboard whatever the settings say, and let clipboard managers show it. Here Copy
/// hands the selection to `onCopy` instead, and nothing reaches the clipboard without it. The edit menu only offers
/// Copy and Select All: Share, Look Up, Translate and the rest would send the text where Vault's settings don't
/// reach, as would dragging it into another app.
final class SelectableTextView: UITextView {
    /// Copies the selected text, applying Vault's clipboard settings.
    var onCopy: ((String) -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        textDragInteraction?.isEnabled = false
        writingToolsBehavior = .none
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// change the cursor to have zero size
    override func caretRect(for _: UITextPosition) -> CGRect {
        .zero
    }

    override var contentSize: CGSize {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: CGSize {
        frame.height > 0 ? contentSize : super.intrinsicContentSize
    }

    override func copy(_: Any?) {
        guard let range = selectedTextRange, let selection = text(in: range), !selection.isEmpty else { return }
        onCopy?(selection)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)), #selector(selectAll(_:)):
            super.canPerformAction(action, withSender: sender)
        default:
            false
        }
    }
}

extension SelectableTextView: UITextViewDelegate {}
