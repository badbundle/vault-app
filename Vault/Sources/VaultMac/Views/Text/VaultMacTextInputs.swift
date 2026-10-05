import AppKit
import SwiftUI

/// A single-line field that edits with `VaultMacFieldEditor`, so nothing typed into it is learned, corrected or sent
/// elsewhere (G52, G89), with its title beside it, as a Mac form lays a field out. Every text field in the Mac app is
/// one of these, a `VaultMacSearchField` or a `VaultMacSecureField`; `VaultMacTextInputDeclarationTests` fails for
/// SwiftUI's own.
struct VaultMacTextField: View {
    var title: String
    @Binding var text: String
    var isMonospaced = false
    /// Set on the AppKit field itself, where UI tests look for it.
    var identifier: String?
    var onSubmit: () -> Void = {}

    init(
        _ title: String,
        text: Binding<String>,
        isMonospaced: Bool = false,
        identifier: String? = nil,
        onSubmit: @escaping () -> Void = {},
    ) {
        self.title = title
        _text = text
        self.isMonospaced = isMonospaced
        self.identifier = identifier
        self.onSubmit = onSubmit
    }

    var body: some View {
        LabeledContent(title) {
            VaultMacTextFieldRepresentable(
                title: title,
                text: $text,
                isMonospaced: isMonospaced,
                identifier: identifier,
                onSubmit: onSubmit,
            )
        }
    }
}

/// The AppKit field inside a `VaultMacTextField`.
private struct VaultMacTextFieldRepresentable: NSViewRepresentable {
    var title: String
    @Binding var text: String
    var isMonospaced: Bool
    var identifier: String?
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> VaultMacNSTextField {
        let field = VaultMacNSTextField()
        field.setAccessibilityLabel(title)
        field.setAccessibilityIdentifier(identifier)
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        if isMonospaced {
            field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        return field
    }

    func updateNSView(_ field: VaultMacNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: VaultMacTextFieldRepresentable

        init(parent: VaultMacTextFieldRepresentable) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

/// An `NSTextField` that edits with `VaultMacFieldEditor`.
final class VaultMacNSTextField: NSTextField {
    override static var cellClass: AnyClass? {
        get { VaultMacTextFieldCell.self }
        set {}
    }
}

/// Hands its field the Vault field editor, rather than the window's shared one.
final class VaultMacTextFieldCell: NSTextFieldCell {
    private lazy var editor = VaultMacFieldEditor.makeFieldEditor()

    override func fieldEditor(for _: NSView) -> NSTextView? {
        editor
    }
}

/// The search field in the main window's toolbar, where killphrases and search passphrases are typed. It edits with
/// `VaultMacFieldEditor`, like every other field.
struct VaultMacSearchField: NSViewRepresentable {
    @Binding var text: String
    /// Changes each time something asks for the field to take focus, as Find (⌘F) does.
    var focusRequest: Int

    func makeNSView(context: Context) -> NSSearchField {
        let field = VaultMacNSSearchField()
        field.placeholderString = "Search"
        field.setAccessibilityIdentifier("feed.search")
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: VaultMacSearchField
        var focusRequest: Int

        init(parent: VaultMacSearchField) {
            self.parent = parent
            focusRequest = parent.focusRequest
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

/// An `NSSearchField` that edits with `VaultMacFieldEditor`.
final class VaultMacNSSearchField: NSSearchField {
    override static var cellClass: AnyClass? {
        get { VaultMacSearchFieldCell.self }
        set {}
    }
}

/// Hands its field the Vault field editor, rather than the window's shared one.
final class VaultMacSearchFieldCell: NSSearchFieldCell {
    private lazy var editor = VaultMacFieldEditor.makeFieldEditor()

    override func fieldEditor(for _: NSView) -> NSTextView? {
        editor
    }
}

/// Multi-line text, such as a note, edited with a `VaultMacFieldEditor` of its own.
struct VaultMacTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isMonospaced = false
    var accessibilityLabel: String
    /// Set on the AppKit text view itself, where UI tests look for it.
    var identifier: String?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = VaultMacFieldEditor(frame: .zero)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = isMonospaced
            ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.copyText = VaultMacFieldEditor.copyToVaultClipboard
        textView.string = text
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.setAccessibilityIdentifier(identifier)
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: VaultMacTextEditor

        init(parent: VaultMacTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

extension VaultMacFieldEditor {
    /// A field editor for a single-line field.
    @MainActor
    static func makeFieldEditor() -> VaultMacFieldEditor {
        let editor = VaultMacFieldEditor(frame: .zero)
        editor.isFieldEditor = true
        editor.copyText = copyToVaultClipboard
        return editor
    }

    /// Copies text being edited through Vault's clipboard, as a detail that never leaves this Mac (G50).
    @MainActor
    static func copyToVaultClipboard(_ text: String) {
        VaultMacRoot.pasteboard.copy(text, as: .detail)
    }
}

/// A secure field as an editor shows it: in a rounded border, with its title beside it, like a `VaultMacTextField`.
/// AppKit's secure field already keeps what's typed from being learned, copied or seen by apps
/// watching the keyboard.
struct VaultMacSecureField: View {
    var title: String
    @Binding var text: String
    /// Whether its title is beside it, as a form row's is, or only its placeholder, as in a grid of words.
    var isLabelled = true
    /// Set on the secure field itself, where UI tests look for it.
    var identifier: String?

    init(_ title: String, text: Binding<String>, isLabelled: Bool = true, identifier: String? = nil) {
        self.title = title
        _text = text
        self.isLabelled = isLabelled
        self.identifier = identifier
    }

    var body: some View {
        if isLabelled {
            LabeledContent(title) {
                field(prompt: nil)
            }
        } else {
            field(prompt: Text(title))
        }
    }

    private func field(prompt: Text?) -> some View {
        SecureField(title, text: $text, prompt: prompt)
            .secretTextInput()
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .accessibilityIdentifier(identifier ?? "")
    }
}
