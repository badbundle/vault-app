import Foundation
import ObjectiveC
import UIKit
import VaultCore

/// Sends Cut and Copy in text being edited through Vault's clipboard, like every other copy Vault makes.
///
/// SwiftUI's text fields and editors have no copy hook. Left to UIKit, their Cut and Copy put the text on the system
/// clipboard with no expiry, offer it to the user's other devices over Universal Clipboard whatever the settings say,
/// and let clipboard managers show it (MANIFESTO C7). SwiftUI draws them with subclasses of `UITextField` and
/// `UITextView` whose `copy(_:)` and `cut(_:)` call through to those classes' own, so once installed, this replaces
/// those two: the selection goes to `Pasteboard.copy(_:as:)` instead, and Cut then deletes it, as the delete key
/// would. The system clipboard never sees it any other way.
///
/// What kind of text it is, for Universal Clipboard, is what the focused `LabeledTextField` says it's copied as: a
/// note's contents follow the Notes setting. Anything else, like a code's setup key, a recovery phrase's words or a
/// search, stays on this device.
///
/// A secure field copies nothing, as UIKit's doesn't. `SelectableTextView` has a `copy(_:)` of its own.
@MainActor
enum EditedTextClipboard {
    /// Where copies go once installed. Without one, Cut and Copy are UIKit's.
    private static var pasteboard: Pasteboard?
    private static var isInstalled = false
    /// The `LabeledTextField` being edited, and what its text is copied as.
    private static var focusedField: (id: UUID, contentType: PasteboardContentType)?

    /// Sends Cut and Copy in text being edited to `pasteboard` from now on.
    static func install(_ pasteboard: Pasteboard) {
        self.pasteboard = pasteboard
        guard !isInstalled else { return }
        isInstalled = true
        for inputClass in [UITextField.self, UITextView.self] as [AnyClass] {
            replace(NSSelectorFromString("copy:"), in: inputClass, cutting: false)
            replace(NSSelectorFromString("cut:"), in: inputClass, cutting: true)
        }
    }

    /// Leaves Cut and Copy to UIKit again, for tests.
    static func uninstall() {
        pasteboard = nil
        focusedField = nil
    }

    /// Called by a `LabeledTextField` as it gains and loses focus, so a copy from it is copied as `contentType`.
    static func field(_ id: UUID, isFocused: Bool, copyingAs contentType: PasteboardContentType) {
        if isFocused {
            focusedField = (id, contentType)
        } else if focusedField?.id == id {
            focusedField = nil
        }
    }

    private static func replace(_ selector: Selector, in inputClass: AnyClass, cutting: Bool) {
        guard let method = class_getInstanceMethod(inputClass, selector) else { return }
        typealias EditAction = @convention(c) (AnyObject, Selector, Any?) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: EditAction.self)
        let replacement: @convention(block) (AnyObject, Any?) -> Void = { input, sender in
            MainActor.assumeIsolated {
                guard let pasteboard, let input = input as? (any UIView & UITextInput) else {
                    original(input, selector, sender)
                    return
                }
                copySelection(of: input, cutting: cutting, to: pasteboard)
            }
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }

    private static func copySelection(of input: any UIView & UITextInput, cutting: Bool, to pasteboard: Pasteboard) {
        guard
            !isSecure(input),
            let range = input.selectedTextRange,
            !range.isEmpty,
            let text = input.text(in: range),
            !text.isEmpty
        else { return }
        pasteboard.copy(text, as: focusedField?.contentType ?? .detail)
        if cutting, isEditable(input) {
            // Deletes the selection as the delete key does, which is what SwiftUI updates the field's text from.
            input.deleteBackward()
        }
    }

    private static func isSecure(_ input: any UIView & UITextInput) -> Bool {
        switch input {
        case let field as UITextField: field.isSecureTextEntry
        case let textView as UITextView: textView.isSecureTextEntry
        default: true
        }
    }

    private static func isEditable(_ input: any UIView & UITextInput) -> Bool {
        switch input {
        case let field as UITextField: field.isEnabled
        case let textView as UITextView: textView.isEditable
        default: false
        }
    }
}
