import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

struct RecoveryPhraseValidationSummaryTests {
    private let locale = Locale(identifier: "en_US")

    @Test
    func validBIP39() {
        let sut = makeSUT(.valid(.bip39(languages: [.english, .french])), wordCount: 12)

        #expect(sut.kind == .valid)
        #expect(sut.title == "Valid BIP39 phrase")
        #expect(sut.detail == "English · French · 12 words")
    }

    @Test
    func validSLIP39() {
        let sut = makeSUT(.valid(.slip39(isExtendable: true)), wordCount: 20)

        #expect(sut.kind == .valid)
        #expect(sut.title == "Valid SLIP-39 share")
        #expect(sut.detail == "20 words")
    }

    @Test
    func validElectrum() {
        let sut = makeSUT(.valid(.electrum(.segwit)), wordCount: 12)

        #expect(sut.kind == .valid)
        #expect(sut.title == "Valid Electrum seed")
        #expect(sut.detail == "SegWit · 12 words")
    }

    @Test
    func validMonero() {
        let sut = makeSUT(.valid(.monero), wordCount: 25)

        #expect(sut.kind == .valid)
        #expect(sut.title == "Valid Monero seed")
        #expect(sut.detail == "25 words")
    }

    @Test
    func unknownSingleWord() {
        let sut = makeSUT(.unknownWords, unknown: [2])

        #expect(sut.kind == .warning)
        #expect(sut.title == "Unrecognized words")
        #expect(sut.detail == "Word 3 isn't in the wordlist. Check it against your backup.")
        #expect(sut.unknownWordPositions == [2])
    }

    @Test
    func unknownMultipleWords() {
        let sut = makeSUT(.unknownWords, unknown: [2, 6, 10])

        #expect(sut.detail == "Words 3, 7, and 11 aren't in the wordlist. Check them against your backup.")
        #expect(sut.unknownWordPositions == [2, 6, 10])
    }

    @Test
    func invalidChecksum() {
        let sut = makeSUT(.invalidChecksum)

        #expect(sut.kind == .warning)
        #expect(sut.title == "Checksum doesn't match")
    }

    @Test
    func invalidShare() {
        let sut = makeSUT(.invalidShare, standard: .slip39)

        #expect(sut.kind == .warning)
        #expect(sut.title == "Invalid share")
    }

    @Test
    func incomplete() {
        let sut = makeSUT(.incomplete, wordCount: 24)

        #expect(sut.kind == .neutral)
        #expect(sut.title == "Incomplete")
        #expect(sut.detail == "Enter all 24 words to check the phrase.")
    }

    @Test
    func unsupportedWordCount() {
        let sut = makeSUT(.unsupportedWordCount, wordCount: 13)

        #expect(sut.kind == .warning)
        #expect(sut.detail == "This type of phrase can't have 13 words.")
    }

    @Test
    func notValidated() {
        #expect(makeSUT(.notValidated, standard: .other).detail
            == "Vault doesn't check the words of this type of phrase.")
        #expect(makeSUT(.notValidated, standard: .bip39).detail
            == "The wordlist couldn't be loaded, so the words can't be checked.")
    }

    @Test(arguments: RecoveryPhraseStandard.allCases)
    func standard_hasLocalizedText(standard: RecoveryPhraseStandard) {
        #expect(standard.localizedTitle.isNotEmpty)
        #expect(!standard.localizedTitle.contains("recoveryPhraseStandard"))
        #expect(standard.localizedSubtitle.isNotEmpty)
        #expect(!standard.localizedSubtitle.contains("recoveryPhraseStandard"))
    }

    @Test(arguments: ElectrumSeedType.allCases)
    func electrumSeedType_hasLocalizedText(seedType: ElectrumSeedType) {
        #expect(seedType.localizedTitle.isNotEmpty)
        #expect(!seedType.localizedTitle.contains("electrumSeedType"))
    }
}

// MARK: - Helpers

extension RecoveryPhraseValidationSummaryTests {
    private func makeSUT(
        _ status: RecoveryPhraseValidation.Status,
        unknown: [Int] = [],
        standard: RecoveryPhraseStandard = .bip39,
        wordCount: Int = 12,
    ) -> RecoveryPhraseValidationSummary {
        RecoveryPhraseValidationSummary(
            validation: .init(status: status, unknownWordPositions: unknown),
            standard: standard,
            wordCount: wordCount,
            locale: locale,
        )
    }
}
