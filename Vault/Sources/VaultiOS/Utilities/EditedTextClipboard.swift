import Foundation
import ObjectiveC
import SwiftUI
import UIKit
import VaultCore

/// Sends Cut and Copy in text being edited through Vault's clipboard, like every other copy Vault makes, and keeps
/// the text from leaving Vault any other way.
///
/// SwiftUI's text fields and editors have no copy hook. Left to UIKit, their Cut and Copy put the text on the system
/// clipboard with no expiry, offer it to the user's other devices over Universal Clipboard whatever the settings say,
/// and let clipboard managers show it (MANIFESTO C7). SwiftUI draws them with subclasses of `UITextField` and
/// `UITextView` whose `copy(_:)` and `cut(_:)` call through to those classes' own, so once installed, this replaces
/// those two: the selection goes to `Pasteboard.copy(_:as:)` instead, and Cut then deletes it, as the delete key
/// would. The system clipboard never sees it any other way.
///
/// The edit menu offers only the editing actions: Cut, Copy, Paste, Select, Select All and Delete, with Undo and Redo
/// kept for the keyboard. Share, Look Up, Translate, Search Web and the rest would send the text where Vault's
/// settings don't reach, and so would dragging it into another app, which is turned off. `SelectableTextView` does
/// the same for text that's only shown.
///
/// What kind of text it is, for Universal Clipboard, is what the focused field says it's copied as
/// (`editedTextCopying(_:isFocused:)`): a note's contents follow the Notes setting. Anything else, like a code's
/// setup key or a search, stays on this device. A field can say it copies nothing, as a recovery phrase's words do.
///
/// A secure field copies nothing, as UIKit's doesn't, and keeps UIKit's own edit menu. `SelectableTextView` has a
/// `copy(_:)` of its own.
@MainActor
enum EditedTextClipboard {
    /// What Cut and Copy do in a field being edited.
    enum Copying: Equatable {
        /// Copy through Vault's clipboard, as this kind of text.
        case text(PasteboardContentType)
        /// Nothing, as in a secure field: Copy copies nothing, and Cut neither copies nor deletes.
        case nothing
    }

    /// Where copies go once installed. Without one, Cut, Copy, the edit menu and dragging are UIKit's.
    private static var pasteboard: Pasteboard?
    private static var isInstalled = false
    /// The field being edited, and what Cut and Copy do in it.
    private static var focusedField: (id: UUID, copying: Copying)?

    /// The actions the edit menu offers in text being edited, and that keyboard shortcuts can perform. Undo and Redo
    /// stay for the keyboard's shortcuts and shaking to undo.
    private static let editingActions = Set(
        ["cut:", "copy:", "paste:", "select:", "selectAll:", "delete:", "undo:", "redo:"].map(NSSelectorFromString),
    )

    /// Sends Cut and Copy in text being edited to `pasteboard` from now on.
    static func install(_ pasteboard: Pasteboard) {
        self.pasteboard = pasteboard
        guard !isInstalled else { return }
        isInstalled = true
        for inputClass in [UITextField.self, UITextView.self] as [AnyClass] {
            replace(NSSelectorFromString("copy:"), in: inputClass, cutting: false)
            replace(NSSelectorFromString("cut:"), in: inputClass, cutting: true)
            limitEditMenu(in: inputClass)
            turnOffTextDrag(in: inputClass)
        }
    }

    /// Leaves Cut, Copy, the edit menu and dragging to UIKit again, for tests. An input already in a window keeps
    /// dragging turned off.
    static func uninstall() {
        pasteboard = nil
        focusedField = nil
    }

    /// Called by a field as it gains and loses focus, so Cut and Copy in it do what `copying` says.
    static func field(_ id: UUID, isFocused: Bool, copying: Copying) {
        if isFocused {
            focusedField = (id, copying)
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

    /// Offers only `editingActions`, of those UIKit would, in an input that isn't secure.
    private static func limitEditMenu(in inputClass: AnyClass) {
        let selector = #selector(UIResponder.canPerformAction(_:withSender:))
        guard let method = class_getInstanceMethod(inputClass, selector) else { return }
        typealias CanPerformAction = @convention(c) (AnyObject, Selector, Selector, Any?) -> Bool
        let original = unsafeBitCast(method_getImplementation(method), to: CanPerformAction.self)
        let replacement: @convention(block) (AnyObject, Selector, Any?) -> Bool = { input, action, sender in
            let canPerform = original(input, selector, action, sender)
            return MainActor.assumeIsolated {
                guard pasteboard != nil, let input = input as? (any UIView & UITextInput), !isSecure(input) else {
                    return canPerform
                }
                return canPerform && editingActions.contains(action)
            }
        }
        setImplementation(of: method, named: selector, in: inputClass, to: replacement)
    }

    /// Turns off dragging text out of an input that isn't secure, once it's in a window.
    private static func turnOffTextDrag(in inputClass: AnyClass) {
        let selector = #selector(UIView.didMoveToWindow)
        guard let method = class_getInstanceMethod(inputClass, selector) else { return }
        typealias DidMoveToWindow = @convention(c) (AnyObject, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: DidMoveToWindow.self)
        let replacement: @convention(block) (AnyObject) -> Void = { input in
            original(input, selector)
            MainActor.assumeIsolated {
                guard pasteboard != nil,
                      let input = input as? (any UIView & UITextInput & UITextDraggable),
                      !isSecure(input)
                else { return }
                input.textDragInteraction?.isEnabled = false
            }
        }
        setImplementation(of: method, named: selector, in: inputClass, to: replacement)
    }

    /// Gives `inputClass` its own implementation of `selector`, rather than changing the one it inherits, which every
    /// other view shares.
    private static func setImplementation(
        of method: Method,
        named selector: Selector,
        in inputClass: AnyClass,
        to block: Any,
    ) {
        let implementation = imp_implementationWithBlock(block)
        if !class_addMethod(inputClass, selector, implementation, method_getTypeEncoding(method)) {
            method_setImplementation(method, implementation)
        }
    }

    private static func copySelection(of input: any UIView & UITextInput, cutting: Bool, to pasteboard: Pasteboard) {
        let copying = focusedField?.copying ?? .text(.detail)
        guard
            !isSecure(input),
            case let .text(contentType) = copying,
            let range = input.selectedTextRange,
            !range.isEmpty,
            let text = input.text(in: range),
            !text.isEmpty
        else { return }
        pasteboard.copy(text, as: contentType)
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

extension View {
    /// Tells `EditedTextClipboard` what Cut and Copy do in this input while it's focused.
    ///
    /// - Parameter isFocused: Whether the input is focused, from the `FocusState` it's bound to.
    func editedTextCopying(_ copying: EditedTextClipboard.Copying, isFocused: Bool) -> some View {
        modifier(EditedTextCopyingModifier(copying: copying, isFocused: isFocused))
    }
}

private struct EditedTextCopyingModifier: ViewModifier {
    var copying: EditedTextClipboard.Copying
    var isFocused: Bool

    /// Identifies this input to `EditedTextClipboard` while it's focused.
    @State private var clipboardID = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isFocused, initial: true) { _, isFocused in
                EditedTextClipboard.field(clipboardID, isFocused: isFocused, copying: copying)
            }
            .onDisappear {
                EditedTextClipboard.field(clipboardID, isFocused: false, copying: copying)
            }
    }
}
