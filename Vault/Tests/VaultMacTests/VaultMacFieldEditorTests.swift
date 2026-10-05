import AppKit
import Carbon.HIToolbox
import Testing
@testable import VaultMac

@MainActor
struct VaultMacFieldEditorTests {
    @Test
    func init_turnsOffEverythingThatLearnsFromWhatsTyped() {
        let sut = VaultMacFieldEditor(frame: .zero)

        #expect(!sut.isContinuousSpellCheckingEnabled)
        #expect(!sut.isGrammarCheckingEnabled)
        #expect(!sut.isAutomaticSpellingCorrectionEnabled)
        #expect(!sut.isAutomaticTextCompletionEnabled)
        #expect(!sut.isAutomaticTextReplacementEnabled)
        #expect(!sut.isAutomaticQuoteSubstitutionEnabled)
        #expect(!sut.isAutomaticDashSubstitutionEnabled)
        #expect(!sut.isAutomaticDataDetectionEnabled)
        #expect(!sut.isAutomaticLinkDetectionEnabled)
        #expect(sut.inlinePredictionType == .no)
        #expect(sut.writingToolsBehavior == .none)
    }

    @Test
    func copy_copiesTheSelectionThroughVaultsClipboardOnly() {
        let sut = VaultMacFieldEditor(frame: .zero)
        var copied: [String] = []
        sut.copyText = { copied.append($0) }
        sut.string = "not this, secret"
        sut.setSelectedRange(NSRange(location: 10, length: 6))
        let changeCount = NSPasteboard.general.changeCount

        sut.copy(nil)

        #expect(copied == ["secret"])
        #expect(NSPasteboard.general.changeCount == changeCount)
    }

    @Test
    func copy_nothingSelected_copiesNothing() {
        let sut = VaultMacFieldEditor(frame: .zero)
        var copied: [String] = []
        sut.copyText = { copied.append($0) }
        sut.string = "secret"
        sut.setSelectedRange(NSRange(location: 0, length: 0))

        sut.copy(nil)

        #expect(copied.isEmpty)
    }

    @Test
    func cut_copiesThroughVaultsClipboardThenRemovesTheSelection() {
        let sut = VaultMacFieldEditor(frame: .zero)
        var copied: [String] = []
        sut.copyText = { copied.append($0) }
        sut.string = "keep secret"
        sut.setSelectedRange(NSRange(location: 4, length: 7))

        sut.cut(nil)

        #expect(copied == [" secret"])
        #expect(sut.string == "keep")
    }

    @Test
    func services_getNothing() {
        let sut = VaultMacFieldEditor(frame: .zero)
        sut.string = "secret"
        sut.selectAll(nil)

        #expect(sut.validRequestor(forSendType: .string, returnType: nil) == nil)
        #expect(sut.validRequestor(forSendType: nil, returnType: .string) == nil)
    }

    @Test
    func menu_offersOnlyThePlainTextActions() {
        let menu = VaultMacFieldEditor.editingMenu()

        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Cut", "Copy", "Paste", "Select All"])
    }

    @Test
    func fields_editWithTheVaultFieldEditor() {
        let textField = VaultMacTextFieldCell().fieldEditor(for: NSView())
        let searchField = VaultMacSearchFieldCell().fieldEditor(for: NSView())

        #expect(textField is VaultMacFieldEditor)
        #expect(textField?.isFieldEditor == true)
        #expect(searchField is VaultMacFieldEditor)
        #expect(searchField?.isFieldEditor == true)
        #expect((VaultMacNSTextField().cell as? VaultMacTextFieldCell) != nil)
        #expect((VaultMacNSSearchField().cell as? VaultMacSearchFieldCell) != nil)
    }

    /// Secure Keyboard Entry is system-wide, and already on while anything else has it, such as a locked screen's
    /// password field, so this only runs while nothing does.
    @Test(.enabled(if: !IsSecureEventInputEnabled(), "Something else has Secure Keyboard Entry on"))
    func focus_turnsOnSecureKeyboardEntryUntilItsLost() {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 200, height: 100),
            styleMask: [],
            backing: .buffered,
            defer: true,
        )
        let sut = VaultMacFieldEditor(frame: .init(x: 0, y: 0, width: 200, height: 20))
        let other = NSView(frame: .init(x: 0, y: 40, width: 200, height: 20))
        window.contentView?.addSubview(sut)
        window.contentView?.addSubview(other)

        window.makeFirstResponder(sut)
        #expect(IsSecureEventInputEnabled())

        window.makeFirstResponder(nil)
        #expect(!IsSecureEventInputEnabled())
    }

    @Test(.enabled(if: !IsSecureEventInputEnabled(), "Something else has Secure Keyboard Entry on"))
    func removedFromItsWindow_turnsOffSecureKeyboardEntry() {
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 200, height: 100),
            styleMask: [],
            backing: .buffered,
            defer: true,
        )
        let sut = VaultMacFieldEditor(frame: .init(x: 0, y: 0, width: 200, height: 20))
        window.contentView?.addSubview(sut)
        window.makeFirstResponder(sut)
        #expect(IsSecureEventInputEnabled())

        sut.removeFromSuperview()

        #expect(!IsSecureEventInputEnabled())
    }
}
