import Foundation
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

struct RecoveryPhraseDetailEditsTests {
    @Test
    func new_hasExpectedDefaults() {
        let sut = RecoveryPhraseDetailEdits.new()

        #expect(sut.standard == .bip39)
        #expect(sut.title == "")
        #expect(sut.contents == "")
        #expect(sut.words == Array(repeating: "", count: 24))
        #expect(sut.lockState == .lockedWithNativeSecurity)
        #expect(sut.previewMode == .titleOnly)
        #expect(sut.viewConfig == .alwaysVisible)
        #expect(sut.passwordState == .required)
        #expect(sut.isValid == false)
    }

    // MARK: - isValid

    @Test
    func isValid_requiresPassword() throws {
        var sut = completeEdits()
        #expect(sut.isValid == false)

        sut.newEncryptionPassword = "password"
        #expect(sut.isValid)

        sut.newEncryptionPassword = ""
        sut.existingEncryptionKey = try anyKey()
        #expect(sut.isValid)
    }

    @Test
    func isValid_blankPasswordIsNotAPassword() {
        var sut = completeEdits()
        sut.newEncryptionPassword = "   "

        #expect(sut.isValid == false)
        #expect(sut.passwordState == .required)
    }

    @Test
    func isValid_requiresEveryWord() {
        var sut = completeEdits()
        sut.newEncryptionPassword = "password"
        sut.applyInput("", at: 4)

        #expect(sut.isValid == false)
    }

    @Test
    func isValid_doesNotRequireValidPhrase() {
        var sut = completeEdits()
        sut.newEncryptionPassword = "password"
        sut.applyInput("notaword", at: 4)
        sut.applyInput("zoo", at: 11)

        #expect(sut.validation.isValid == false)
        #expect(sut.isValid, "Invalid phrases are warned about, but can still be saved")
    }

    @Test
    func isValid_requiresSearchPassphraseWhenHidden() {
        var sut = completeEdits()
        sut.newEncryptionPassword = "password"
        sut.viewConfig = .requiresSearchPassphrase
        #expect(sut.isValid == false)

        sut.searchPassphrase = "search"
        #expect(sut.isValid)
    }

    @Test
    func passwordState() throws {
        var sut = completeEdits()
        #expect(sut.passwordState == .required)

        sut.newEncryptionPassword = "new"
        #expect(sut.passwordState == .set)

        sut.existingEncryptionKey = try anyKey()
        #expect(sut.passwordState == .willChange)

        sut.newEncryptionPassword = ""
        #expect(sut.passwordState == .set)
    }

    // MARK: - Word count

    @Test
    func setWordCount_keepsEnteredWords() {
        var sut = completeEdits()

        sut.setWordCount(24)
        #expect(sut.words == validBIP39Words + Array(repeating: "", count: 12))

        sut.setWordCount(12)
        #expect(sut.words == validBIP39Words)
    }

    @Test
    func setWordCount_clampsToSupportedCount() {
        var sut = RecoveryPhraseDetailEdits.new()

        sut.setWordCount(13)

        #expect(sut.wordCount == 12)
    }

    @Test
    func setStandard_resizesToNearestSupportedCount() {
        var sut = completeEdits()

        sut.setStandard(.slip39)
        #expect(sut.wordCount == 20)
        #expect(Array(sut.words.prefix(12)) == validBIP39Words)

        sut.setStandard(.monero)
        #expect(sut.wordCount == 25)

        sut.setStandard(.other)
        #expect(sut.wordCount == 25)

        sut.setStandard(.bip39)
        #expect(sut.wordCount == 24)
    }

    // MARK: - Input

    @Test
    func applyInput_keepsTypingAsEntered() {
        var sut = RecoveryPhraseDetailEdits.new()

        let next = sut.applyInput("Aban", at: 3)

        #expect(sut.words[3] == "Aban")
        #expect(next == nil)
    }

    @Test
    func applyInput_trailingSpaceMovesToNextWord() {
        var sut = RecoveryPhraseDetailEdits.new()

        let next = sut.applyInput("abandon ", at: 3)

        #expect(sut.words[3] == "abandon")
        #expect(next == 4)
    }

    @Test
    func applyInput_onlyWhitespaceClearsWord() {
        var sut = RecoveryPhraseDetailEdits.new()
        sut.applyInput("abandon", at: 0)

        let next = sut.applyInput(" ", at: 0)

        #expect(sut.words[0] == "")
        #expect(next == nil)
    }

    @Test
    func applyInput_pasteFillsFollowingWords() {
        var sut = RecoveryPhraseDetailEdits.new()

        let next = sut.applyInput("ability able about", at: 5)

        #expect(sut.words[5 ... 7] == ["ability", "able", "about"])
        #expect(next == 8)
        #expect(sut.wordCount == 24)
    }

    @Test
    func applyInput_pastingWholePhraseResizes() {
        var sut = RecoveryPhraseDetailEdits.new()
        let numbered = validBIP39Words.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let next = sut.applyInput(numbered, at: 0)

        #expect(sut.words == validBIP39Words)
        #expect(next == nil)
        #expect(sut.validation.isValid)
    }

    @Test
    func applyInput_pasteOfUnsupportedLengthDoesNotResize() {
        var sut = RecoveryPhraseDetailEdits.new()
        sut.setWordCount(12)

        sut.applyInput(Array(repeating: "zoo", count: 14).joined(separator: " "), at: 0)

        #expect(sut.words == Array(repeating: "zoo", count: 12))
    }

    @Test
    func applyInput_pasteIntoOtherResizesToAnyLength() {
        var sut = RecoveryPhraseDetailEdits.new()
        sut.setStandard(.other)

        sut.applyInput("one two three four five", at: 0)

        #expect(sut.words == ["one", "two", "three", "four", "five"])
    }

    @Test
    func applyInput_ignoresOutOfRangePosition() {
        var sut = RecoveryPhraseDetailEdits.new()

        #expect(sut.applyInput("abandon", at: 24) == nil)
        #expect(sut.words == Array(repeating: "", count: 24))
    }

    // MARK: - makeRecoveryPhrase

    @Test
    func makeRecoveryPhrase_usesCanonicalSpellingWhenValid() {
        var sut = completeEdits()
        sut.applyInput("ABANDON", at: 0)
        sut.title = "  Title  "

        let phrase = sut.makeRecoveryPhrase()

        #expect(phrase.words == validBIP39Words)
        #expect(phrase.title == "Title")
        #expect(phrase.standard == .bip39)
    }

    @Test
    func makeRecoveryPhrase_keepsInvalidWordsAsEnteredButTrimmed() {
        var sut = completeEdits()
        sut.applyInput("NotAWord", at: 0)

        let phrase = sut.makeRecoveryPhrase()

        #expect(phrase.words.first == "NotAWord")
    }

    @Test
    func makeRecoveryPhrase_keepsPassphraseExactly() {
        var sut = completeEdits()
        sut.seedPassphrase = "  Pass Phrase \n"

        #expect(sut.makeRecoveryPhrase().passphrase == "  Pass Phrase \n")
        #expect(sut.seedPassphraseHasSurroundingWhitespace)
    }

    @Test
    func makeRecoveryPhrase_includesTrimmedContents() {
        var sut = completeEdits()
        sut.contents = "\n  Ledger in the drawer\nSecond line  \n"

        #expect(sut.makeRecoveryPhrase().contents == "Ledger in the drawer\nSecond line")
    }

    @Test
    func isValid_doesNotRequireContentsOrTitle() {
        var sut = completeEdits()
        sut.newEncryptionPassword = "password"

        #expect(sut.title.isEmpty)
        #expect(sut.contents.isEmpty)
        #expect(sut.isValid)
    }

    @Test
    func seedPassphraseHasSurroundingWhitespace() {
        var sut = completeEdits()

        #expect(sut.seedPassphraseHasSurroundingWhitespace == false)
        sut.seedPassphrase = "inner space"
        #expect(sut.seedPassphraseHasSurroundingWhitespace == false)
        sut.seedPassphrase = "trailing "
        #expect(sut.seedPassphraseHasSurroundingWhitespace)
    }
}

// MARK: - Helpers

extension RecoveryPhraseDetailEditsTests {
    /// Every word of a valid phrase entered, but no password.
    private func completeEdits() -> RecoveryPhraseDetailEdits {
        var edits = RecoveryPhraseDetailEdits.new()
        edits.setWordCount(12)
        for (index, word) in validBIP39Words.enumerated() {
            edits.applyInput(word, at: index)
        }
        return edits
    }

    private func anyKey() throws -> DerivedEncryptionKey {
        try VaultKeyDeriver.testing.createEncryptionKey(password: "any")
    }
}
