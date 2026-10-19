import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

struct PrivateKeyDetailEditsTests {
    @Test
    func new_isBlankAndOnlyPreviewsTheTitle() {
        let sut = PrivateKeyDetailEdits.new()

        #expect(sut.key == "")
        #expect(sut.title == "")
        #expect(sut.previewMode == .titleOnly)
        #expect(sut.passwordState == .required)
        #expect(sut.isValid == false)
    }

    /// Always locked: there's nothing to change it with (G102).
    @Test
    func lockState_isAlwaysLocked() {
        #expect(PrivateKeyDetailEdits.new().lockState == .lockedWithNativeSecurity)
    }

    @Test
    func isComplete_contentNeedsAKey() {
        var sut = PrivateKeyDetailEdits.new()
        #expect(!sut.isComplete(.content))

        sut.key = "   \n"
        #expect(!sut.isComplete(.content))

        // Anything at all: a key Vault doesn't recognize, or that doesn't validate, can still be saved.
        sut.key = "not a format Vault knows"
        #expect(sut.isComplete(.content))
    }

    /// Always encrypted: it can't be saved without a password.
    @Test
    func isComplete_securityNeedsAPassword() {
        var sut = PrivateKeyDetailEdits.new()
        sut.key = validWIFKey
        #expect(!sut.isComplete(.security))
        #expect(!sut.isValid)

        sut.newEncryptionPassword = "password"
        #expect(sut.isComplete(.security))
        #expect(sut.isValid)
    }

    @Test
    func passwordState_followsThePasswordAndTheExistingKey() {
        var sut = PrivateKeyDetailEdits.new()
        #expect(sut.passwordState == .required)
        sut.newEncryptionPassword = "new"
        #expect(sut.passwordState == .set)

        sut.existingEncryptionKey = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        #expect(sut.passwordState == .willChange)
        sut.newEncryptionPassword = ""
        #expect(sut.passwordState == .set)
    }

    @Test
    func makePrivateKey_trimsTheTitleDescriptionAndKey() {
        var sut = PrivateKeyDetailEdits.new()
        sut.title = "  Title  "
        sut.contents = "\n Description \n"
        sut.key = "\n  some other text  \n"

        #expect(sut.makePrivateKey() == PrivateKey(title: "Title", key: "some other text", contents: "Description"))
    }

    /// A single-line key split over lines is saved as the wallet needs it.
    @Test
    func makePrivateKey_savesAValidSingleLineKeyWithoutTheWhitespaceInIt() {
        var sut = PrivateKeyDetailEdits.new()
        sut.key = String(validWIFKey.prefix(10)) + "\n" + String(validWIFKey.dropFirst(10))

        #expect(sut.makePrivateKey().key == validWIFKey)
    }

    /// Text Vault doesn't recognize keeps its whitespace: only a key whose format says it has none loses it.
    @Test
    func makePrivateKey_keepsTheWhitespaceInsideOtherText() {
        var sut = PrivateKeyDetailEdits.new()
        sut.key = "line one\nline two"

        #expect(sut.makePrivateKey().key == "line one\nline two")
    }

    @Test
    func validation_isTheValidatorsForTheKey() {
        var sut = PrivateKeyDetailEdits.new()
        sut.key = validWIFKey

        #expect(sut.validation == PrivateKeyValidator.validate(validWIFKey))
    }
}
