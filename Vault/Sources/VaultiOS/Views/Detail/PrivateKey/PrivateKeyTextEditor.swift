import SwiftUI
import UIKit
import VaultFeed

/// The field a private key is typed or pasted into: a text view that wraps the key between any two characters, and
/// never hyphenates it.
///
/// SwiftUI's `TextEditor` hyphenates a long word where it wraps, whatever it's told, so a key would show with a hyphen
/// that isn't in it. This text view wraps by character, with hyphenation off, and grows with the key, as a block of
/// armored text needs.
///
/// Like every other field, it declares `secretTextInput(_:)`, which it sets the keyboard up with, and the keyboard
/// learns nothing typed into it. Cut and Copy do nothing in it, as in a recovery phrase's words: it tells
/// `EditedTextClipboard` so while it's being edited, and dragging text out of it is off, as for every field.
struct PrivateKeyTextEditor: UIViewRepresentable {
    @Binding var text: String
    var accessibilityLabel: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byCharWrapping
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.dataDetectorTypes = []
        textView.isFindInteractionEnabled = false
        textView.accessibilityLabel = accessibilityLabel
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        Self.keepKeyboardFromLearning(textView, input: context.environment.secretTextInput ?? .verbatim)
        textView.typingAttributes = Self.attributes
        textView.attributedText = NSAttributedString(string: text, attributes: Self.attributes)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        Self.keepKeyboardFromLearning(textView, input: context.environment.secretTextInput ?? .verbatim)
        guard textView.text != text else { return }
        textView.attributedText = NSAttributedString(string: text, attributes: Self.attributes)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context _: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let minimumHeight = (uiView.font?.lineHeight ?? 22) * 3
        return CGSize(width: width, height: max(fitting.height, minimumHeight))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleUIView(_: UITextView, coordinator: Coordinator) {
        EditedTextClipboard.field(coordinator.clipboardID, isFocused: false, copying: .nothing)
    }

    /// Monospaced at the body text size, scaled with Dynamic Type, and never hyphenated.
    static var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.hyphenationFactor = 0
        paragraph.usesDefaultHyphenation = false
        let font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: UIFont.labelFontSize, weight: .regular))
        return [.font: font, .paragraphStyle: paragraph, .foregroundColor: UIColor.label]
    }

    /// What `secretTextInput(_:)` sets up on SwiftUI's own fields: no autocorrection, and so no predictions and
    /// nothing learned, no Writing Tools, and capitals and the keyboard as declared. Nothing typed is "smartened".
    private static func keepKeyboardFromLearning(_ textView: UITextView, input: SecretTextInput) {
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.inlinePredictionType = .no
        textView.writingToolsBehavior = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocapitalizationType = switch input.capitalization {
        case .never: .none
        case .sentences: .sentences
        case .characters: .allCharacters
        }
        textView.keyboardType = input.isASCIIOnly ? .asciiCapable : .default
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PrivateKeyTextEditor
        /// Identifies this field to `EditedTextClipboard` while it's being edited.
        let clipboardID = UUID()

        init(parent: PrivateKeyTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_: UITextView) {
            EditedTextClipboard.field(clipboardID, isFocused: true, copying: .nothing)
        }

        func textViewDidEndEditing(_: UITextView) {
            EditedTextClipboard.field(clipboardID, isFocused: false, copying: .nothing)
        }
    }
}
