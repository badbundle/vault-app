import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

struct SecureNoteDetailEditsTests {
    @Test
    func isValid_validForTitleWithContents() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "Nice"

        #expect(sut.isValid)
    }

    @Test
    func isValid_invalidForEmptySearchPassphrase() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.viewConfig = .requiresSearchPassphrase
        sut.searchPassphrase = ""

        #expect(sut.isValid == false)
    }

    @Test
    func isValid_validForNonEmptySearchPassphrase() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.viewConfig = .requiresSearchPassphrase
        sut.searchPassphrase = "passphrase"

        #expect(sut.isValid)
    }

    @Test
    func title_isFirstLineOfContent() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "First\nSecond\nThird"

        #expect(sut.titleLine == "First")
    }

    @Test
    func title_skipsEmptyLines() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "\n\nFirst\n\nSecond\nThird"

        #expect(sut.titleLine == "First")
    }

    @Test
    func contentPreviewLine_isSecondLineOfContent() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "First\nSecond\nThird"

        #expect(sut.contentPreviewLine == "Second")
    }

    @Test
    func contentPreviewLine_isEmptyIfNoSecondLine() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "First"

        #expect(sut.contentPreviewLine == "")
    }

    @Test
    func contentPreviewLine_skipsEmptyLines() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "\n\nFirst\n\nSecond\nThird"

        #expect(sut.contentPreviewLine == "Second")
    }

    @Test
    func contentPreviewLine_isEmptyIfNoteEncrpyted() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "First\n\nSecond\nThird"
        sut.existingEncryptionKey = .init(key: .random(), salt: .random(count: 10), keyDervier: .testing)

        #expect(sut.contentPreviewLine == "")
    }

    @Test
    func contentPreviewLine_isEmptyIfNoteAboutToBeENcrpyted() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "First\n\nSecond\nThird"
        sut.newEncryptionPassword = "password"

        #expect(sut.contentPreviewLine == "")
    }

    @Test
    func contentPreviewLine_isEmptyWhenPreviewModeIsTitleOnly() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "First\nSecond\nThird"
        sut.previewMode = .titleOnly

        #expect(sut.contentPreviewLine == "")
    }

    @Test
    func contentPreviewLine_isEmptyWhenPreviewModeIsHidden() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "First\nSecond\nThird"
        sut.previewMode = .hidden

        #expect(sut.contentPreviewLine == "")
    }

    @Test
    func isValid_validWhenExistingSearchPassphraseRequiresBlankPassphrase() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())
        sut.contents = "Nice"
        sut.viewConfig = .requiresSearchPassphrase
        sut.hasExistingSearchPassphrase = true
        sut.searchPassphrase = ""

        #expect(sut.isValid)
    }

    @Test
    func killphrasePropertiesReflectEnabledState() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())

        #expect(sut.killphraseIsEnabled == false)
        #expect(sut.killphraseEnabledText == "None")
        #expect(sut.killphraseEnabledIcon == "bolt")

        sut.killphraseEnabled = true

        #expect(sut.killphraseIsEnabled)
        #expect(sut.killphraseEnabledText == "Enabled")
        #expect(sut.killphraseEnabledIcon == "bolt.badge.checkmark.fill")
    }

    @Test
    func encryptionTextReflectsEncryptionState() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())

        #expect(sut.encrypted == false)
        #expect(sut.encryptionEnabledText == "None")

        sut.newEncryptionPassword = "password"

        #expect(sut.encrypted)
        #expect(sut.encryptionEnabledText == "Enabled")
    }

    @Test
    func isKillphraseValid_rejectsWhitespaceOnlyValue() {
        var sut = SecureNoteDetailEdits.new(defaults: NewItemDefaults())

        sut.newKillphrase = ""
        #expect(sut.isKillphraseValid)

        sut.newKillphrase = "phrase"
        #expect(sut.isKillphraseValid)

        sut.newKillphrase = "   "
        #expect(sut.isKillphraseValid == false)
    }
}
