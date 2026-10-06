import Foundation
import Testing

/// Every text field in the Mac app edits with `VaultMacFieldEditor`, or is a `SecureField`.
///
/// SwiftUI's `TextField`, `TextEditor` and `searchable` edit with AppKit's shared field editor, which spell checks,
/// completes and offers Services and Writing Tools to whatever's typed. So the Mac app's sources use
/// `VaultMacTextField`, `VaultMacTextEditor` and `VaultMacSearchField` instead, and this fails for any of SwiftUI's.
/// The iOS tests' `SecretTextInputDeclarationTests` checks every `SecureField` declares `secretTextInput()`.
struct VaultMacTextInputDeclarationTests {
    static let forbidden = ["TextField(", "TextEditor(", ".searchable("]

    @Test
    func noSwiftUITextFieldsInTheMacApp() throws {
        let uses = try Self.lines(in: Self.macSources()).filter { line in
            Self.forbidden.contains { line.code.contains(callTo: $0) }
        }

        #expect(
            uses.isEmpty,
            """
            Use VaultMacTextField, VaultMacTextEditor or VaultMacSearchField, which edit with VaultMacFieldEditor, \
            rather than SwiftUI's own (docs/mac-app.md, "The keyboard and text"). On:
            \(uses.map(\.description).joined(separator: "\n"))
            """,
        )
    }

    /// Guards against the check passing because it found nothing to check.
    @Test
    func findsTheMacAppsFields() throws {
        let lines = try Self.lines(in: Self.macSources())

        #expect(lines.contains { $0.file == "VaultMacCodeEditor.swift" && $0.code.contains("VaultMacTextField(") })
        #expect(lines.contains { $0.file == "VaultMacNoteEditor.swift" && $0.code.contains("VaultMacTextEditor(") })
        #expect(lines.contains { $0.file == "VaultMacMainView.swift" && $0.code.contains("VaultMacSearchField(") })
    }

    @Test
    func scanner_matchesOnlySwiftUIsNames() {
        #expect("TextField(\"Name\", text: $name)".contains(callTo: "TextField("))
        #expect("SwiftUI.TextField(\"Name\", text: $name)".contains(callTo: "TextField("))
        #expect(!"VaultMacTextField(\"Name\", text: $name)".contains(callTo: "TextField("))
        #expect(!"NSTextField(labelWithString: title)".contains(callTo: "TextField("))
        #expect(".searchable(text: $query)".contains(callTo: ".searchable("))
    }
}

extension VaultMacTextInputDeclarationTests {
    struct Line {
        var file: String
        var number: Int
        var code: String

        var description: String {
            "\(file):\(number): \(code.trimmingCharacters(in: .whitespaces))"
        }
    }

    static func macSources() throws -> [URL] {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent() // VaultMacTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Vault
        let root = repository.appending(path: "Sources/VaultMac")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Each line's code, without comments.
    static func lines(in files: [URL]) throws -> [Line] {
        try files.flatMap { url in
            try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .compactMap { index, line -> Line? in
                    let code = line.trimmingCharacters(in: .whitespaces)
                    guard !code.hasPrefix("//"), !code.hasPrefix("*"), !code.hasPrefix("/*") else { return nil }
                    return Line(file: url.lastPathComponent, number: index + 1, code: String(line))
                }
        }
    }
}

extension String {
    /// Whether this calls `name`, rather than something whose name only ends with it.
    fileprivate func contains(callTo name: String) -> Bool {
        var searchStart = startIndex
        while let range = self[searchStart...].range(of: name) {
            let isWholeName = name.first == "." || range.lowerBound == startIndex
                || !(self[index(before: range.lowerBound)].isLetter || self[index(before: range.lowerBound)].isNumber)
            if isWholeName {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }
}
