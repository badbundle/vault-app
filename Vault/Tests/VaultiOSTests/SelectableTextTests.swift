import Foundation
import SwiftUI
import TestHelpers
import Testing
import UIKit
import VaultCore
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
struct SelectableTextTests {
    // MARK: - SelectableTextView

    @Test
    func copy_handsTheSelectionToOnCopy() {
        let sut = makeTextView(text: "Network: Guest")
        var copied = [String]()
        sut.onCopy = { copied.append($0) }
        sut.selectedRange = NSRange(location: 9, length: 5)

        sut.copy(nil)

        #expect(copied == ["Guest"])
    }

    @Test
    func copy_withoutASelectionCopiesNothing() {
        let sut = makeTextView(text: "Network: Guest")
        var copied = [String]()
        sut.onCopy = { copied.append($0) }
        sut.selectedRange = NSRange(location: 0, length: 0)

        sut.copy(nil)

        #expect(copied.isEmpty)
    }

    @Test
    func canPerformAction_onlyOffersCopyAndSelectAll() {
        let sut = makeTextView(text: "Network: Guest")
        sut.selectedRange = NSRange(location: 0, length: 7)

        #expect(sut.canPerformAction(NSSelectorFromString("copy:"), withSender: nil))
        #expect(!sut.canPerformAction(NSSelectorFromString("cut:"), withSender: nil))
        #expect(!sut.canPerformAction(NSSelectorFromString("paste:"), withSender: nil))
        // Share, Look Up and Translate send the text elsewhere.
        #expect(!sut.canPerformAction(NSSelectorFromString("_share:"), withSender: nil))
        #expect(!sut.canPerformAction(NSSelectorFromString("_define:"), withSender: nil))
        #expect(!sut.canPerformAction(NSSelectorFromString("_translate:"), withSender: nil))
    }

    @Test
    func init_cantBeDraggedOrRewritten() {
        let sut = SelectableTextView(frame: .zero)

        #expect(sut.textDragInteraction?.isEnabled != true)
        #expect(sut.writingToolsBehavior == .none)
    }

    // MARK: - SelectableText

    @Test(arguments: PasteboardContentType.allCases)
    func selectableText_copiesThroughVaultsClipboard(contentType: PasteboardContentType) throws {
        let clipboard = try Clipboard()

        try copy(
            "Guest",
            from: SelectableText("Network: Guest", fontStyle: .normal, textStyle: .body, copyingAs: contentType),
            with: clipboard.pasteboard,
        )

        let copy = try #require(clipboard.copies.first)
        #expect(clipboard.copies.count == 1)
        #expect(copy.string == "Guest")
        #expect(copy.ttl == 30)
        #expect(copy.localOnly == !clipboard.settings.state.isUniversalClipboardAllowed(for: contentType))
    }

    // MARK: - Where Vault shows selectable text

    @Test(arguments: [false, true])
    func plainNote_copyFollowsTheNotesSetting(allowNotes: Bool) throws {
        let clipboard = try Clipboard { $0.allowUniversalClipboardForNotes = allowNotes }
        let viewModel = SecureNoteDetailViewModel(
            mode: .editing(
                note: .init(title: "Home Wi-Fi", contents: "Home Wi-Fi\nNetwork: Guest", format: .plain),
                metadata: anyVaultItemMetadata(),
                existingKey: nil,
            ),
            dataModel: anyVaultDataModel(),
            editor: SecureNoteDetailEditorMock(),
        )

        try copy(
            "Guest",
            from: SecureNoteDetailView(viewModel: viewModel, navigationPath: .constant(NavigationPath()))
                .environment(DeviceAuthenticationService(policy: .alwaysAllow)),
            with: clipboard.pasteboard,
        )

        let copy = try #require(clipboard.copies.first)
        #expect(copy.string == "Guest")
        #expect(copy.ttl == 30)
        #expect(copy.localOnly == !allowNotes)
    }

    @Test(arguments: [false, true])
    func formattedNoteSelection_copyFollowsTheNotesSetting(allowNotes: Bool) throws {
        let clipboard = try Clipboard { $0.allowUniversalClipboardForNotes = allowNotes }

        try copy(
            "Guest",
            from: NoteTextSelectionSheet(text: "# Home Wi-Fi\n\nNetwork: **Guest**"),
            with: clipboard.pasteboard,
        )

        let copy = try #require(clipboard.copies.first)
        #expect(copy.string == "Guest")
        #expect(copy.ttl == 30)
        #expect(copy.localOnly == !allowNotes)
    }

    @Test
    func description_copyStaysOnThisDeviceWhateverTheSettings() throws {
        let clipboard = try Clipboard { state in
            state.allowUniversalClipboardForOTPs = true
            state.allowUniversalClipboardForNotes = true
        }

        try copy(
            "badbundle",
            from: Form {
                DetailPageDescriptionSection(title: "Description", text: "Sign-in code for the badbundle org.")
            },
            with: clipboard.pasteboard,
        )

        let copy = try #require(clipboard.copies.first)
        #expect(copy.string == "badbundle")
        #expect(copy.ttl == 30)
        #expect(copy.localOnly)
    }
}

// MARK: - Helpers

extension SelectableTextTests {
    /// Vault's clipboard, recording what reaches the system's. Clear Clipboard is 30 seconds.
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
            systemPasteboard.copyHandler = { [unowned self] string, ttl, localOnly in
                copies.append(Copy(string: string, ttl: ttl, localOnly: localOnly))
            }
        }
    }

    private func makeTextView(text: String) -> SelectableTextView {
        let textView = SelectableTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        textView.text = text
        textView.isEditable = false
        textView.isSelectable = true
        return textView
    }

    /// Shows `view` in a window, then selects `substring` in its selectable text and copies it, as the edit menu's
    /// Copy does.
    ///
    /// SwiftUI only makes the text view once the view is in a window. The test runner has no scene to put one in, so
    /// this uses the window initializer that doesn't take a scene, deprecated as it is.
    @diagnose(DeprecatedDeclaration, as: ignored)
    private func copy(_ substring: String, from view: some View, with pasteboard: Pasteboard) throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIHostingController(rootView: view.environment(pasteboard))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer {
            window.isHidden = true
        }

        let textView = try #require(findTextView(in: controller.view))
        let range = (textView.text as NSString).range(of: substring)
        try #require(range.location != NSNotFound)
        textView.selectedRange = range
        textView.copy(nil)
    }

    private func findTextView(in view: UIView) -> SelectableTextView? {
        if let textView = view as? SelectableTextView {
            return textView
        }
        return view.subviews.lazy.compactMap(findTextView(in:)).first
    }
}
