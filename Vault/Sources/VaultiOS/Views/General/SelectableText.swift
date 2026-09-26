import Combine
import Foundation
import SwiftUI
import UIKit
import VaultCore

/// Text the user can select and copy, where a copy follows Vault's clipboard settings for `contentType`.
///
/// Use it in place of SwiftUI's `textSelection(_:)`, whose copy goes straight to the system clipboard. See
/// `SelectableTextView`.
struct SelectableText: UIViewRepresentable {
    typealias UIViewType = SelectableTextView

    enum FontStyle {
        case normal, monospace
    }

    /// Where the text sits in the space it's given.
    enum Layout {
        /// Inset from the edges, for text that fills a card on its own, like a note.
        case page
        /// Flush to its frame, like a SwiftUI `Text`, for text laid out with other views.
        case inline
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Optional, so a preview without one still renders. Without it nothing is copied.
    @Environment(Pasteboard.self) private var pasteboard: Pasteboard?

    private var text: String
    private var fontStyle: FontStyle
    private var textStyle: UIFont.TextStyle
    private var contentType: PasteboardContentType
    private var layout: Layout

    init(
        _ text: String,
        fontStyle: FontStyle,
        textStyle: UIFont.TextStyle,
        copyingAs contentType: PasteboardContentType,
        layout: Layout = .page,
    ) {
        self.text = text
        self.fontStyle = fontStyle
        self.textStyle = textStyle
        self.contentType = contentType
        self.layout = layout
    }

    func makeUIView(context: Context) -> SelectableTextView {
        let textView = SelectableTextView(frame: .zero)
        textView.delegate = textView
        textView.text = text
        textView.adjustsFontForContentSizeCategory = true
        textView.font = fontStyle.makeFont(size: textStyle, dynamicTypeSize: context.environment.dynamicTypeSize)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        switch layout {
        case .page:
            textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        case .inline:
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
        }
        textView.textColor = .label
        textView.backgroundColor = .clear
        return textView
    }

    func updateUIView(_ uiView: SelectableTextView, context: Context) {
        // Only when it's changed: setting it clears the selection, which would leave nothing for Copy.
        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = fontStyle.makeFont(size: textStyle, dynamicTypeSize: context.environment.dynamicTypeSize)
        uiView.onCopy = { [pasteboard, contentType] selection in
            pasteboard?.copy(selection, as: contentType)
        }
        uiView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SelectableTextView, context _: Context) -> CGSize? {
        let size = CGSize(
            width: proposal.width ?? .greatestFiniteMagnitude,
            height: proposal.height ?? .greatestFiniteMagnitude,
        )
        return uiView.sizeThatFits(size)
    }
}

extension SelectableText.FontStyle {
    /// Derives from the text style's own font, so weight and tracking match the
    /// style rather than being scaled up from a fixed 16pt base.
    ///
    /// `preferredFont(forTextStyle:compatibleWith:)` is already scaled for the
    /// given content size category, so it must not be passed through
    /// `UIFontMetrics` as well.
    func makeFont(size: UIFont.TextStyle, dynamicTypeSize: DynamicTypeSize) -> UIFont {
        let traitCollection = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.contentSizeCategory)
        let preferred = UIFont.preferredFont(forTextStyle: size, compatibleWith: traitCollection)
        switch self {
        case .normal:
            return preferred
        case .monospace:
            return .monospacedSystemFont(ofSize: preferred.pointSize, weight: .regular)
        }
    }
}
