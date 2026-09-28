import Foundation
import SwiftUI
import TestHelpers
import Testing
import UIKit
import UniformTypeIdentifiers
import VaultCore
import VaultFeed
import VaultSettings
@testable import VaultiOS

/// Serialized: installing replaces Cut and Copy for every text input in the process.
@MainActor
@Suite(.serialized)
struct EditedTextClipboardTests {
    // MARK: - Every kind of SwiftUI text input

    @Test(arguments: InputKind.allCases)
    func copy_goesThroughVaultsClipboard(kind: InputKind) async throws {
        let clipboard = try Clipboard()
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("Network: Guest")
        let input = try await hostedInput(kind.view(text: text.binding))

        try select("Guest", in: input)
        send("copy:", to: input)

        #expect(clipboard.copies.map(\.string) == ["Guest"])
        #expect(clipboard.copies.first?.ttl == 30)
        #expect(clipboard.copies.first?.localOnly == true)
        #expect(text.value == "Network: Guest")
    }

    @Test(arguments: InputKind.allCases)
    func cut_copiesThroughVaultsClipboardAndDeletesTheSelection(kind: InputKind) async throws {
        let clipboard = try Clipboard()
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("Network: Guest")
        let input = try await hostedInput(kind.view(text: text.binding))

        try select(": Guest", in: input)
        send("cut:", to: input)
        try await settle()

        #expect(clipboard.copies.map(\.string) == [": Guest"])
        #expect(clipboard.copies.first?.ttl == 30)
        // The field as shown. A single-line field hosted here doesn't pass edits back to its binding, even typed
        // ones, so this doesn't check that: Cut deletes with the delete key's own `deleteBackward()`, as typing does.
        #expect(uikitText(of: input) == "Network")
    }

    @Test
    func copy_withoutASelection_copiesNothing() async throws {
        let clipboard = try Clipboard()
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("Network: Guest")
        let input = try await hostedInput(InputKind.textField.view(text: text.binding))

        input.selectedTextRange = input.textRange(from: input.endOfDocument, to: input.endOfDocument)
        send("copy:", to: input)

        #expect(clipboard.copies.isEmpty)
    }

    @Test
    func secureField_copiesNothing() async throws {
        let clipboard = try Clipboard()
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("correct horse")
        let input = try await hostedInput(
            LabeledTextField("Password", text: text.binding, kind: .secure()).secretTextInput(.verbatim),
            where: { ($0 as? UITextField)?.isSecureTextEntry == true },
        )

        send("selectAll:", to: input)
        send("copy:", to: input)

        #expect(clipboard.copies.isEmpty)
    }

    // MARK: - Edit menu and dragging

    /// Of what UIKit would offer, only the editing actions stay: nothing that sends the text to another app or
    /// service, such as Share, Look Up, Translate or Search Web.
    @Test(arguments: InputKind.allCases)
    func editMenu_offersOnlyEditingActions(kind: InputKind) async throws {
        let clipboard = try Clipboard()
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("Network: Guest")
        let input = try await hostedInput(kind.view(text: text.binding))
        try select("Guest", in: input)

        let offeredByUIKit = offeredActions(in: input, installing: nil)
        let offered = offeredActions(in: input, installing: clipboard.pasteboard)

        // UIKit offers some of the others, so leaving them out means something.
        #expect(!offeredByUIKit.isSubset(of: Self.editingActions), "\(offeredByUIKit)")
        #expect(offered == offeredByUIKit.intersection(Self.editingActions))
        #expect(offered.contains("copy:"))
        #expect(offered.contains("cut:"))
    }

    /// A secure field's edit menu is UIKit's own.
    @Test
    func secureField_editMenuIsUIKits() async throws {
        let clipboard = try Clipboard()
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("correct horse")
        let input = try await hostedInput(
            LabeledTextField("Password", text: text.binding, kind: .secure()).secretTextInput(.verbatim),
            where: { ($0 as? UITextField)?.isSecureTextEntry == true },
        )
        send("selectAll:", to: input)

        let offeredByUIKit = offeredActions(in: input, installing: nil)
        let offered = offeredActions(in: input, installing: clipboard.pasteboard)

        #expect(offered == offeredByUIKit)
    }

    /// Text being edited can't be dragged into another app.
    @Test(arguments: InputKind.allCases)
    func textDrag_isOff(kind: InputKind) async throws {
        _ = try Clipboard()
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("Network: Guest")
        let input = try await hostedInput(kind.view(text: text.binding))

        let draggable = try #require(input as? any UITextDraggable)
        #expect(draggable.textDragInteraction?.isEnabled == false)
    }

    @Test
    func uninstalled_leavesTextDragToUIKit() async throws {
        EditedTextClipboard.uninstall()
        let text = EditedText("Network: Guest")
        let input = try await hostedInput(InputKind.textEditor.view(text: text.binding))

        let draggable = try #require(input as? any UITextDraggable)
        #expect(draggable.textDragInteraction?.isEnabled == true)
    }

    // MARK: - Recovery phrase words

    /// A recovery phrase's words are never copied, even while they're typed: Copy copies nothing, and Cut neither
    /// copies nor deletes.
    @Test
    func recoveryPhraseWord_copiesNothing() async throws {
        let clipboard = try Clipboard()
        defer { EditedTextClipboard.uninstall() }
        let viewModel = RecoveryPhraseDetailViewModel(
            mode: .creating,
            dataModel: anyVaultDataModel(),
            editor: RecoveryPhraseDetailEditorMock(),
            locale: Locale(identifier: "en_US"),
        )
        viewModel.startEditing()
        viewModel.editingModel.detail.setWordCount(12)
        _ = viewModel.editingModel.detail.applyInput("abandon", at: 0)
        viewModel.areWordsRevealed = true
        let input = try await hostedInput(
            RecoveryPhraseWordsStep(viewModel: viewModel, isSeedPassphraseRevealed: .constant(false)),
        )
        #expect(uikitText(of: input) == "abandon")

        try select("aban", in: input)
        send("copy:", to: input)
        send("cut:", to: input)
        try await settle()

        #expect(clipboard.copies.isEmpty)
        #expect(uikitText(of: input) == "abandon")
    }

    // MARK: - What it's copied as

    @Test(arguments: [false, true])
    func noteContents_copyFollowsTheNotesSetting(allowNotes: Bool) async throws {
        let clipboard = try Clipboard { $0.allowUniversalClipboardForNotes = allowNotes }
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("Home Wi-Fi\nNetwork: Guest")
        let input = try await hostedInput(
            LabeledTextField("Contents", text: text.binding, kind: .multiline(minLines: 4), copying: .text(.note))
                .secretTextInput(.prose),
        )

        try select("Guest", in: input)
        send("copy:", to: input)

        #expect(clipboard.copies.map(\.string) == ["Guest"])
        #expect(clipboard.copies.first?.localOnly == !allowNotes)
    }

    /// A code's setup key, a description or a passphrase: none of them is ever offered to other devices.
    @Test
    func otherFields_copyStaysOnThisDeviceWhateverTheSettings() async throws {
        let clipboard = try Clipboard { state in
            state.allowUniversalClipboardForOTPs = true
            state.allowUniversalClipboardForNotes = true
        }
        defer { EditedTextClipboard.uninstall() }
        let text = EditedText("JBSWY3DPEHPK3PXP")
        let input = try await hostedInput(
            LabeledTextField("Setup Key", text: text.binding).secretTextInput(.verbatim),
        )

        try select("JBSWY3DP", in: input)
        send("copy:", to: input)

        #expect(clipboard.copies.map(\.string) == ["JBSWY3DP"])
        #expect(clipboard.copies.first?.localOnly == true)
    }

    // MARK: - Not installed

    @Test
    func uninstalled_leavesCutAndCopyToUIKit() async throws {
        let clipboard = try Clipboard()
        EditedTextClipboard.uninstall()
        let text = EditedText("Network: Guest")
        let input = try await hostedInput(InputKind.textField.view(text: text.binding))

        try select(": Guest", in: input)
        send("cut:", to: input)
        try await settle()

        #expect(clipboard.copies.isEmpty)
        #expect(uikitText(of: input) == "Network")
    }

    // MARK: - Dragging a card

    /// A card is dragged to reorder the feed, as its ID. It offers no text that another app could take.
    @Test
    func vaultItem_draggedOffersItsIDAndNoText() {
        let provider = NSItemProvider()
        provider.register(uniqueVaultItem())

        #expect(provider.registeredContentTypes.contains(UTType(importedAs: "vault.identifier.drop.id")))
        #expect(!provider.registeredContentTypes.contains { $0.conforms(to: .text) })
    }
}

// MARK: - Helpers

extension EditedTextClipboardTests {
    enum InputKind: CaseIterable, CustomTestStringConvertible {
        /// A single line: SwiftUI's `UITextField`.
        case textField
        /// A `TextEditor`, as a multiline `LabeledTextField` uses.
        case textEditor
        /// A `TextField` that grows downwards, as the recovery phrase's words and the search field don't, but could.
        case verticalTextField

        @MainActor
        func view(text: Binding<String>) -> AnyView {
            switch self {
            case .textField:
                AnyView(LabeledTextField("Name", text: text).secretTextInput(.verbatim))
            case .textEditor:
                AnyView(LabeledTextField("Notes", text: text, kind: .multiline(minLines: 3)).secretTextInput(.prose))
            case .verticalTextField:
                AnyView(TextField("Word", text: text, axis: .vertical).secretTextInput(.verbatim))
            }
        }

        var testDescription: String {
            switch self {
            case .textField: "text field"
            case .textEditor: "text editor"
            case .verticalTextField: "vertical text field"
            }
        }
    }

    /// Text a hosted view edits, readable after the view has changed it.
    @MainActor
    private final class EditedText {
        private(set) var value: String

        init(_ value: String) {
            self.value = value
        }

        var binding: Binding<String> {
            Binding { self.value } set: { self.value = $0 }
        }
    }

    /// Vault's clipboard, recording what reaches the system's, and installed as where Cut and Copy go. Each test
    /// uninstalls it when it ends. Clear Clipboard is 30 seconds.
    @MainActor
    private final class Clipboard {
        struct Copy {
            var string: String
            var ttl: Double?
            var localOnly: Bool
        }

        let settings: LocalSettings
        let pasteboard: Pasteboard
        private(set) var copies = [Copy]()

        init(configure: (inout LocalSettingsState) -> Void = { _ in }) throws {
            settings = try LocalSettings(defaults: .nonPersistent())
            settings.state.pasteTimeToLive = PasteTTL(duration: 30)
            configure(&settings.state)
            let systemPasteboard = SystemPasteboardMock()
            pasteboard = Pasteboard(systemPasteboard, localSettings: settings)
            systemPasteboard.copyHandler = { [weak self] string, ttl, localOnly in
                self?.copies.append(Copy(string: string, ttl: ttl, localOnly: localOnly))
            }
            EditedTextClipboard.install(pasteboard)
        }
    }

    /// Hosts `view` in a window and starts editing the UIKit text input SwiftUI made for it: the first one holding
    /// some text, unless `isInput` picks another.
    ///
    /// SwiftUI only makes the input once the view is in a window. The test runner has no scene to put one in, so this
    /// uses the window initializer that doesn't take a scene, deprecated as it is.
    @diagnose(DeprecatedDeclaration, as: ignored)
    private func hostedInput(
        _ view: some View,
        where isInput: (any UIView & UITextInput) -> Bool = { input in
            guard let all = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument) else {
                return false
            }
            return input.text(in: all)?.isEmpty == false
        },
    ) async throws -> any UIView & UITextInput {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let controller = UIHostingController(rootView: Form { view })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        Self.windows.append(window)

        let found = inputs(in: controller.view).first(where: isInput)
        let input = try #require(found)
        input.becomeFirstResponder()
        // Lets SwiftUI see the focus: a `LabeledTextField` tells the clipboard what it's copied as once it does.
        try await settle()
        return input
    }

    /// Windows kept up for the rest of the run, as taking one down while SwiftUI is still updating it can crash.
    private static var windows = [UIWindow]()

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    private func inputs(in view: UIView) -> [any UIView & UITextInput] {
        let own = (view as? (any UIView & UITextInput)).map { [$0] } ?? []
        return own + view.subviews.flatMap(inputs(in:))
    }

    private func uikitText(of input: any UIView & UITextInput) -> String? {
        input.textRange(from: input.beginningOfDocument, to: input.endOfDocument).flatMap { input.text(in: $0) }
    }

    /// Edit menu actions UIKit can offer in text: the editing actions, and others it offers depending on the text,
    /// the selection and the device.
    private static let menuActions: Set<String> = editingActions.union([
        "_share:", "_define:", "_lookup:", "_translate:", "_searchWeb:", "_findSelected:", "_showTextStyleOptions:",
        "_promptForReplace:", "_transliterateChinese:", "_accessibilitySpeak:", "_accessibilitySpeakLanguageSelection:",
        "_addShortcut:", "captureTextFromCamera:", "find:", "findAndReplace:", "findNext:", "findPrevious:",
        "useSelectionForFind:", "toggleBoldface:", "toggleItalics:", "toggleUnderline:", "pasteAndMatchStyle:",
        "makeTextWritingDirectionLeftToRight:", "makeTextWritingDirectionRightToLeft:", "replace:", "showWritingTools:",
        "print:", "increaseSize:", "decreaseSize:",
    ])

    /// What the edit menu keeps once installed.
    private static let editingActions: Set<String> = [
        "cut:", "copy:", "paste:", "select:", "selectAll:", "delete:", "undo:", "redo:",
    ]

    /// Which of `menuActions` the input offers, with Vault's clipboard installed on `pasteboard`, or uninstalled.
    private func offeredActions(
        in input: any UIView & UITextInput,
        installing pasteboard: Pasteboard?,
    ) -> Set<String> {
        if let pasteboard {
            EditedTextClipboard.install(pasteboard)
        } else {
            EditedTextClipboard.uninstall()
        }
        return Self.menuActions.filter { input.canPerformAction(NSSelectorFromString($0), withSender: nil) }
    }

    /// Sends an edit action to the input, as the edit menu and keyboard shortcuts do.
    private func send(_ action: String, to input: any UIView & UITextInput) {
        _ = input.perform(NSSelectorFromString(action), with: nil)
    }

    private func select(_ substring: String, in input: any UIView & UITextInput) throws {
        let all = try #require(input.textRange(from: input.beginningOfDocument, to: input.endOfDocument))
        let text = try #require(input.text(in: all))
        let range = (text as NSString).range(of: substring)
        try #require(range.location != NSNotFound)
        let start = try #require(input.position(from: input.beginningOfDocument, offset: range.location))
        let end = try #require(input.position(from: start, offset: range.length))
        input.selectedTextRange = input.textRange(from: start, to: end)
    }
}
