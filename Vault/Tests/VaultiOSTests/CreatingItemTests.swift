import Foundation
import Testing
@testable import VaultiOS

struct CreatingItemTests {
    /// Every add flow offers recovery phrases and private keys first, then notes, then codes.
    @Test
    func addOrder_recoveryPhrasesAndPrivateKeysFirst() {
        #expect(CreatingItem.addOrder == [.recoveryPhrase, .privateKey, .secureNote, .otpCode])
    }

    @Test
    func addOrder_offersEveryKindOnce() {
        let kinds: [CreatingItem] = [.otpCode, .secureNote, .recoveryPhrase, .privateKey]

        #expect(Set(CreatingItem.addOrder) == Set(kinds))
        #expect(CreatingItem.addOrder.count == kinds.count)
    }

    @Test
    func titlesAndSubtitles_describeEachKind() {
        let described = CreatingItem.addOrder.map { [$0.title, $0.subtitle] }

        #expect(described == [
            ["Recovery Phrase", "Seed words for a crypto wallet"],
            ["Private Key", "A wallet's private or extended key, or a PGP or SSH key"],
            ["Note", "Any text, like a PIN or a password"],
            ["Code", "Two-factor codes for websites and apps"],
        ])
    }
}
