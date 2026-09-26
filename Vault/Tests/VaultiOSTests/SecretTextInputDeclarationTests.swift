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
        let calls = TextInputCallScanner.calls(in: """
        LabeledTextField("Title", text: $title)
            .secretTextInput(.prose)
            .focused($focus, equals: .title)
        """)

        #expect(calls == [.init(name: "LabeledTextField", line: 1, modifiers: ["secretTextInput", "focused"])])
    }

    @Test
    func scanner_findsFieldWithoutModifiers() {
        let calls = TextInputCallScanner.calls(in: """
        VStack {
            Text("Name")
            TextField("Name", text: $name)
        }
        """)

        #expect(calls == [.init(name: "TextField", line: 3, modifiers: [])])
    }

    @Test
    func scanner_readsPastTrailingClosures() {
        let calls = TextInputCallScanner.calls(in: """
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
        let calls = TextInputCallScanner.calls(in: """
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
        let calls = TextInputCallScanner.calls(in: """
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
        let calls = TextInputCallScanner.calls(in: #"""
        LabeledTextField("Name (\(count) \"left\")", text: $name, prompt: "\(example ? "a)" : "b(")")
            .secretTextInput(.prose)
        TextField(#"Raw ")" string"#, text: $raw)
        """#)

        #expect(calls.map(\.modifiers) == [["secretTextInput"], []])
    }

    @Test
    func scanner_ignoresFieldsInCommentsAndStrings() {
        let calls = TextInputCallScanner.calls(in: """
        /// Use `TextField(text:)` rather than a `UITextField`.
        // TextEditor(text: $text)
        /* SecureField(text: $text) /* nested */ */
        Text("LabeledTextField(title)")
        """)

        #expect(calls.isEmpty)
    }

    @Test
    func scanner_ignoresDeclarationsAndOtherNames() {
        let calls = TextInputCallScanner.calls(in: """
        struct LabeledTextField: View {}
        extension LabeledTextField.Status {}
        MyTextField(text: $text)
        """)

        #expect(calls.isEmpty)
    }

    @Test
    func scanner_findsModuleQualifiedFields() {
        let calls = TextInputCallScanner.calls(in: """
        SwiftUI.TextField("Name", text: $name)
        """)

        #expect(calls == [.init(name: "TextField", line: 1, modifiers: [])])
    }
}

// MARK: - Helpers

extension SecretTextInputDeclarationTests {
    struct LocatedCall: CustomStringConvertible {
        /// Relative to the repository.
        var path: String
        var call: TextInputCallScanner.Call

        var file: String {
            URL(filePath: path).lastPathComponent
        }

        var description: String {
            "\(path):\(call.line): \(call.name)"
        }
    }

    /// The Swift package's sources and the app targets' own, found from this file's path.
    private static func textInputCallsInAppSources(filePath: String = #filePath) throws -> [LocatedCall] {
        let repository = URL(filePath: filePath)
            .deletingLastPathComponent() // VaultiOSTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Vault
            .deletingLastPathComponent()
        let roots = [
            repository.appending(path: "Vault/Sources"),
            repository.appending(path: "VaultApp"),
        ]
        var calls: [LocatedCall] = []
        for root in roots {
            let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let url as URL in files where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                let path = String(url.standardizedFileURL.path().dropFirst(repository.standardizedFileURL.path().count))
                for call in TextInputCallScanner.calls(in: source) {
                    calls.append(LocatedCall(path: path, call: call))
                }
            }
        }
        return calls
    }
}
