import AppKit
import Carbon.HIToolbox
import Quartz
import VaultCore

/// The text view every Vault field edits with: its own field editor for single-line fields, and the text view of a
/// note (docs/mac-app.md, "The keyboard and text").
///
/// - Nothing typed is checked, corrected, completed, predicted or replaced: spelling and grammar checking,
///   autocorrection, text completion, inline predictions and every substitution are off (G52).
/// - Writing Tools and the Services menu get nothing from it.
/// - Cut and Copy go through Vault's clipboard (G50, G51), and its menu has only the plain text actions.
/// - While it has focus, Secure Keyboard Entry is on, so apps watching the keyboard see nothing typed
///   (docs/mac-app.md, decision 8).
final class VaultMacFieldEditor: NSTextView {
    /// Where Cut and Copy put the text: Vault's clipboard, as the app has it.
    var copyText: (@MainActor (String) -> Void)?
    private var hasSecureInput = false

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        Self.turnOffLearning(self)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Self.turnOffLearning(self)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Turns off everything that could learn from what's typed, change it, or send it elsewhere.
    static func turnOffLearning(_ textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.inlinePredictionType = .no
        textView.writingToolsBehavior = .none
        textView.allowsCharacterPickerTouchBarItem = false
        textView.usesFindPanel = false
    }

    /// The field editor as Vault sets it up, after AppKit has set it up for a field, which turns some of this back on.
    /// A single-line field keeps no undo history: its text can be a killphrase or a search passphrase.
    static func keepPrivate(_ text: NSText) -> NSText {
        if let textView = text as? NSTextView {
            turnOffLearning(textView)
            textView.allowsUndo = false
        }
        return text
    }

    /// Turns off what a field itself would hand its field editor as editing starts.
    static func turnOffLearning(in field: NSTextField) {
        field.isAutomaticTextCompletionEnabled = false
        field.allowsCharacterPickerTouchBarItem = false
        (field.cell as? NSTextFieldCell)?.allowsUndo = false
    }

    // MARK: - Look Up

    /// Look Up (a force click, or ⌃⌘D) shows nothing, and sends nothing to Apple's Look Up services.
    override func quickLook(with _: NSEvent) {}

    override func showDefinition(for _: NSAttributedString?, at _: NSPoint) {}

    override func quickLookPreviewableItems(inRanges _: [NSValue]) -> [any QLPreviewItem] {
        []
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, !hasSecureInput {
            EnableSecureEventInput()
            hasSecureInput = true
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            endSecureInput()
        }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            endSecureInput()
        }
    }

    private func endSecureInput() {
        guard hasSecureInput else { return }
        DisableSecureEventInput()
        hasSecureInput = false
    }

    // MARK: - Clipboard

    @objc override func copy(_: Any?) {
        guard let selected = selectedText else { return }
        copyText?(selected)
    }

    @objc override func cut(_ sender: Any?) {
        guard selectedText != nil else { return }
        copy(sender)
        delete(sender)
    }

    /// What's selected, if anything is.
    var selectedText: String? {
        let range = selectedRange()
        guard range.length > 0, let text = (string as NSString?)?.substring(with: range) else { return nil }
        return text
    }

    /// Nothing is dragged out of a field into another app (G51).
    override func dragSelection(with _: NSEvent, offset _: NSSize, slideBack _: Bool) -> Bool {
        false
    }

    // MARK: - Services and menus

    override func validRequestor(
        forSendType _: NSPasteboard.PasteboardType?,
        returnType _: NSPasteboard.PasteboardType?,
    )
        -> Any?
    {
        nil
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        Self.editingMenu()
    }

    /// Cut, Copy, Paste and Select All: what a field's menu offers, and nothing else (G51).
    static func editingMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        return menu
    }
}
