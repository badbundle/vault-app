import AppKit
import SwiftUI

/// The search field in the main window's toolbar, where killphrases and search passphrases are typed, and in the
/// AutoFill sheet. It edits with `VaultMacFieldEditor`, like every other field.
public struct VaultMacSearchField: NSViewRepresentable {
    @Binding var text: String
    /// Changes each time something asks for the field to take focus, as Find (⌘F) does.
    var focusRequest: Int
    /// Where Cut and Copy put what's selected: Vault's clipboard, or nowhere, as in the AutoFill sheet.
    var copyText: (@MainActor (String) -> Void)?

    public init(text: Binding<String>, focusRequest: Int, copyText: (@MainActor (String) -> Void)?) {
        _text = text
        self.focusRequest = focusRequest
        self.copyText = copyText
    }

    public func makeNSView(context: Context) -> NSSearchField {
        let field = VaultMacNSSearchField()
        VaultMacFieldEditor.turnOffLearning(in: field)
        (field.cell as? VaultMacSearchFieldCell)?.copyText = copyText
        field.placeholderString = "Search"
        field.setAccessibilityIdentifier("feed.search")
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        return field
    }

    public func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: VaultMacSearchField
        var focusRequest: Int

        init(parent: VaultMacSearchField) {
            self.parent = parent
            focusRequest = parent.focusRequest
        }

        public func controlTextDidChange(_ notification: Notification) {
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

/// Hands its field the Vault field editor, rather than the window's shared one, and keeps it as Vault set it up each
/// time editing starts.
final class VaultMacSearchFieldCell: NSSearchFieldCell {
    private lazy var editor = VaultMacFieldEditor.makeFieldEditor(copyText: nil)

    /// Where Cut and Copy put what's selected: nowhere, unless the field says otherwise.
    var copyText: (@MainActor (String) -> Void)? {
        get { editor.copyText }
        set { editor.copyText = newValue }
    }

    override func fieldEditor(for _: NSView) -> NSTextView? {
        editor
    }

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        VaultMacFieldEditor.keepPrivate(super.setUpFieldEditorAttributes(textObj))
    }
}
