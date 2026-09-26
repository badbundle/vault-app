import Foundation
import Testing

/// Every text input in the app declares how it sets up the keyboard.
///
/// A text field left to the system's defaults lets the keyboard autocorrect, predict and learn from what's typed, and
/// what the keyboard learns lives outside the vault. So every `TextField`, `SecureField`, `TextEditor` and
/// `LabeledTextField` in the app's sources, including the AutoFill extension and widgets, has to chain
/// `.secretTextInput(_:)` onto its declaration.
struct SecretTextInputDeclarationTests {
    @Test
    func everyTextInputDeclaresSecretTextInput() throws {
        let calls = try Self.textInputCallsInAppSources()

        let undeclared = calls.filter { !$0.call.modifiers.contains("secretTextInput") }
        #expect(
            undeclared.isEmpty,
            """
            Chain .secretTextInput(_:) onto every text input, to keep the keyboard from learning what's typed and to \
            decide how it capitalizes (see SecretTextInput). Missing on:
            \(undeclared.map(\.description).joined(separator: "\n"))
            """,
        )
    }

    /// Guards against the check passing because it found nothing to check.
    @Test
    func findsTheTextInputsInTheAppSources() throws {
        let calls = try Self.textInputCallsInAppSources()

        #expect(calls.contains { $0.file == "VaultItemFeedView.swift" && $0.call.name == "TextField" })
        #expect(calls.contains { $0.file == "LabeledTextField.swift" && $0.call.name == "TextEditor" })
        #expect(calls.contains { $0.file == "SecureNoteEditorSteps.swift" && $0.call.name == "LabeledTextField" })
    }
}

// MARK: - Scanner

extension SecretTextInputDeclarationTests {
    @Test
    func scanner_findsModifiersChainedOntoAField() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: """
        LabeledTextField("Title", text: $title)
            .secretTextInput(.prose)
            .focused($focus, equals: .title)
        """)

        #expect(calls == [.init(name: "LabeledTextField", line: 1, modifiers: ["secretTextInput", "focused"])])
    }

    @Test
    func scanner_findsFieldWithoutModifiers() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: """
        VStack {
            Text("Name")
            TextField("Name", text: $name)
        }
        """)

        #expect(calls == [.init(name: "TextField", line: 3, modifiers: [])])
    }

    @Test
    func scanner_readsPastTrailingClosures() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: """
        SecureField(text: $text, prompt: nil) {
            Text(title)
        }
        .onSubmit {
            submit()
        }
        .secretTextInput(.verbatim)
        """)

        #expect(calls.map(\.modifiers) == [["onSubmit", "secretTextInput"]])
    }

    @Test
    func scanner_readsPastLabeledTrailingClosures() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: """
        TextField(text: $text) {
            Text("Word")
        } label: {
            EmptyView()
        }
        .secretTextInput(.verbatim)
        """)

        #expect(calls.map(\.modifiers) == [["secretTextInput"]])
    }

    @Test
    func scanner_readsPastCommentsInTheChain() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: """
        TextEditor(text: $text)
            // Line it up with the label.
            .padding(insets)
            /* The keyboard. */
            .secretTextInput(.prose)
        """)

        #expect(calls.map(\.modifiers) == [["padding", "secretTextInput"]])
    }

    @Test
    func scanner_isNotThrownByBracketsOrQuotesInStrings() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: #"""
        LabeledTextField("Name (\(count) \"left\")", text: $name, prompt: "\(example ? "a)" : "b(")")
            .secretTextInput(.prose)
        TextField(#"Raw ")" string"#, text: $raw)
        """#)

        #expect(calls.map(\.modifiers) == [["secretTextInput"], []])
    }

    @Test
    func scanner_ignoresFieldsInCommentsAndStrings() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: """
        /// Use `TextField(text:)` rather than a `UITextField`.
        // TextEditor(text: $text)
        /* SecureField(text: $text) /* nested */ */
        Text("LabeledTextField(title)")
        """)

        #expect(calls.isEmpty)
    }

    @Test
    func scanner_ignoresDeclarationsAndOtherNames() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: """
        struct LabeledTextField: View {}
        extension LabeledTextField.Status {}
        MyTextField(text: $text)
        """)

        #expect(calls.isEmpty)
    }

    @Test
    func scanner_findsModuleQualifiedFields() {
        let calls = ViewCallScanner.calls(to: Self.textInputNames, in: """
        SwiftUI.TextField("Name", text: $name)
        """)

        #expect(calls == [.init(name: "TextField", line: 1, modifiers: [])])
    }
}

// MARK: - Helpers

extension SecretTextInputDeclarationTests {
    /// SwiftUI's text inputs, and the app's own field built from them.
    static let textInputNames: Set = ["TextField", "SecureField", "TextEditor", "LabeledTextField"]

    private static func textInputCallsInAppSources() throws -> [ViewCallScanner.LocatedCall] {
        try ViewCallScanner.callsInAppSources(to: textInputNames)
    }
}
