import Foundation
import Testing
@testable import VaultCore

struct RecoveryPhraseValidatorTests {
    // MARK: - BIP39

    @Test(arguments: RecoveryPhraseTestVectors.bip39Valid)
    func validate_bip39ValidVectors(language: BIP39Language, phrase: String) {
        let words = RecoveryPhraseInput.words(in: phrase)

        let result = RecoveryPhraseValidator.validate(words: words, standard: .bip39)

        guard case let .valid(.bip39(languages)) = result.status else {
            Issue.record("Expected valid BIP39 phrase, got \(result.status)")
            return
        }
        #expect(languages.contains(language))
        #expect(result.unknownWordPositions.isEmpty)
        #expect(result.missingWordPositions.isEmpty)
        #expect(result.canonicalWords?.count == words.count)
    }

    @Test(arguments: RecoveryPhraseTestVectors.bip39InvalidChecksum)
    func validate_bip39SwappedWordsHaveInvalidChecksum(language _: BIP39Language, phrase: String) {
        let words = RecoveryPhraseInput.words(in: phrase)

        let result = RecoveryPhraseValidator.validate(words: words, standard: .bip39)

        #expect(result.status == .invalidChecksum)
        #expect(result.unknownWordPositions.isEmpty)
    }

    @Test
    func validate_bip39EveryWordCountIsCovered() {
        let counts = Set(RecoveryPhraseTestVectors.bip39Valid.map { RecoveryPhraseInput.words(in: $0.1).count })

        #expect(counts == Set(RecoveryPhraseStandard.bip39.supportedWordCounts))
    }

    /// Both phrases only use words that are in the English and French lists (found, and checked, with
    /// `Mnemonic.check` from trezor/python-mnemonic).
    @Test(arguments: [
        ("impact cycle million stable bicycle canal prison civil label romance bonus civil", [BIP39Language.english]),
        ("bicycle excuse badge question crucial guide mobile cruel public correct rival phrase", [.english, .french]),
    ])
    func validate_bip39WordsSharedBetweenLanguagesUseTheChecksum(phrase: String, expected: [BIP39Language]) {
        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .bip39)

        #expect(result.status == .valid(.bip39(languages: expected)))
    }

    @Test
    func validate_bip39ToleratesCaseAndMissingAccents() throws {
        let valid = try #require(RecoveryPhraseTestVectors.bip39Valid.first { $0.0 == .spanish && $0.1.contains("á") })
        let words = RecoveryPhraseInput.words(in: valid.1)
        let unaccented = words.map { word in
            var ascii = String.UnicodeScalarView()
            ascii.append(contentsOf: word.decomposedStringWithCanonicalMapping.unicodeScalars.filter(\.isASCII))
            return String(ascii).uppercased()
        }
        #expect(unaccented != words)

        let result = RecoveryPhraseValidator.validate(words: unaccented, standard: .bip39)

        #expect(result.isValid)
        #expect(result.canonicalWords == words.map(\.precomposedStringWithCanonicalMapping))
    }

    @Test
    func validate_bip39ReportsUnknownWordPositions() {
        var words = Array(repeating: "abandon", count: 11) + ["about"]
        words[2] = "notaword"
        words[7] = "abandonn"

        let result = RecoveryPhraseValidator.validate(words: words, standard: .bip39)

        #expect(result.status == .unknownWords)
        #expect(result.unknownWordPositions == [2, 7])
        #expect(result.canonicalWords == nil)
    }

    @Test
    func validate_incompleteWhenWordsAreBlank() {
        var words = Array(repeating: "abandon", count: 11) + ["about"]
        words[3] = ""
        words[5] = "   "

        let result = RecoveryPhraseValidator.validate(words: words, standard: .bip39)

        #expect(result.status == .incomplete)
        #expect(result.missingWordPositions == [3, 5])
        #expect(result.unknownWordPositions.isEmpty)
    }

    @Test
    func validate_unknownWordsTakePrecedenceOverIncomplete() {
        var words = Array(repeating: "", count: 12)
        words[0] = "abandon"
        words[1] = "notaword"

        let result = RecoveryPhraseValidator.validate(words: words, standard: .bip39)

        #expect(result.status == .unknownWords)
        #expect(result.unknownWordPositions == [1])
        #expect(result.missingWordPositions == Array(2 ..< 12))
    }

    @Test(arguments: [
        (RecoveryPhraseStandard.bip39, 13),
        (.bip39, 11),
        (.bip39, 25),
        (.slip39, 19),
        (.slip39, 21),
        (.electrum, 14),
        (.electrum, 11),
        (.monero, 24),
        (.monero, 26),
    ])
    func validate_unsupportedWordCount(standard: RecoveryPhraseStandard, wordCount: Int) {
        // Words that are in every list, so the only problem is the count.
        let word = standard == .slip39 ? "academic" : (standard == .monero ? "abbey" : "abandon")
        let words = Array(repeating: word, count: wordCount)

        let result = RecoveryPhraseValidator.validate(words: words, standard: standard)

        #expect(result.status == .unsupportedWordCount)
        #expect(result.canonicalWords == nil)
    }

    @Test
    func validate_ignoresWhitespaceAroundWords() {
        let words = (Array(repeating: "abandon", count: 11) + ["about"]).map { " \($0)\n" }

        let result = RecoveryPhraseValidator.validate(words: words, standard: .bip39)

        #expect(result.isValid)
        #expect(result.canonicalWords == validTwelveWords)
    }

    @Test
    func validate_bip39EmptyPhraseIsIncomplete() {
        let result = RecoveryPhraseValidator.validate(words: Array(repeating: "", count: 24), standard: .bip39)

        #expect(result.status == .incomplete)
        #expect(result.missingWordPositions == Array(0 ..< 24))
        #expect(result.unknownWordPositions.isEmpty)
    }

    // MARK: - SLIP-39

    @Test(arguments: RecoveryPhraseTestVectors.slip39Valid)
    func validate_slip39ValidShares(isExtendable: Bool, phrase: String) {
        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .slip39)

        #expect(result.status == .valid(.slip39(isExtendable: isExtendable)))
    }

    @Test
    func validate_slip39CoversBothLengthsAndExtendability() {
        let vectors = RecoveryPhraseTestVectors.slip39Valid
        let counts = Set(vectors.map { RecoveryPhraseInput.words(in: $0.1).count })

        #expect(counts == [20, 33])
        #expect(vectors.contains { $0.0 })
        #expect(vectors.contains { !$0.0 })
    }

    @Test(arguments: RecoveryPhraseTestVectors.slip39InvalidChecksum)
    func validate_slip39InvalidChecksum(phrase: String) {
        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .slip39)

        #expect(result.status == .invalidChecksum)
    }

    @Test(arguments: RecoveryPhraseTestVectors.slip39InvalidShare)
    func validate_slip39MalformedShare(phrase: String) {
        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .slip39)

        #expect(result.status == .malformed)
    }

    @Test
    func validate_slip39UnknownWord() throws {
        let valid = try #require(RecoveryPhraseTestVectors.slip39Valid.first)
        var words = RecoveryPhraseInput.words(in: valid.1)
        words[4] = "abandon" // BIP39, but not SLIP-39

        let result = RecoveryPhraseValidator.validate(words: words, standard: .slip39)

        #expect(result.status == .unknownWords)
        #expect(result.unknownWordPositions == [4])
    }

    @Test
    func validate_slip39CanonicalWordsAreLowercase() throws {
        let valid = try #require(RecoveryPhraseTestVectors.slip39Valid.first)
        let words = RecoveryPhraseInput.words(in: valid.1)

        let result = RecoveryPhraseValidator.validate(words: words.map { $0.uppercased() }, standard: .slip39)

        #expect(result.isValid)
        #expect(result.canonicalWords == words)
    }

    @Test
    func validate_slip39SwappedWordsHaveInvalidChecksum() throws {
        let valid = try #require(RecoveryPhraseTestVectors.slip39Valid.first)
        var words = RecoveryPhraseInput.words(in: valid.1)
        try #require(words[5] != words[9])
        words.swapAt(5, 9)

        let result = RecoveryPhraseValidator.validate(words: words, standard: .slip39)

        #expect(result.status == .invalidChecksum)
    }

    // MARK: - Electrum

    @Test(arguments: RecoveryPhraseTestVectors.electrumValid)
    func validate_electrumValidSeeds(seedType: ElectrumSeedType, phrase: String) {
        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .electrum)

        #expect(result.status == .valid(.electrum(seedType)))
    }

    @Test(arguments: RecoveryPhraseTestVectors.electrumInvalid)
    func validate_electrumInvalidSeeds(phrase: String) {
        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .electrum)

        #expect(result.status == .invalidChecksum)
    }

    @Test
    func validate_electrumUnknownWord() {
        // From Electrum's own tests: "ca" is a typo of "can".
        let phrase = "science dawn member doll dutch real ca brick knife deny drive list"

        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .electrum)

        #expect(result.status == .unknownWords)
        #expect(result.unknownWordPositions == [6])
    }

    /// Electrum seeds don't depend on a wordlist, so a registered version number makes a seed valid whatever its
    /// words. The seed was found (and checked) with Electrum's `normalize_text` and `calc_seed_type`.
    @Test
    func validate_electrumValidWithWordsOutsideAnyWordlist() {
        let phrase = "wild father tree among universe vaultword838 mobile favorite target dynamic credit identify"
        let words = RecoveryPhraseInput.words(in: phrase)

        let result = RecoveryPhraseValidator.validate(words: words, standard: .electrum)

        #expect(result.status == .valid(.electrum(.standard)))
        #expect(result.unknownWordPositions.isEmpty)
        #expect(result.canonicalWords == words)
    }

    @Test
    func validate_electrumWordNotInAnySupportedList() {
        // A BIP39 Czech word: Czech isn't one of the lists Electrum creates seeds from.
        var words = "wild father tree among universe such mobile favorite target dynamic credit identify"
            .split(separator: " ").map(String.init)
        words[0] = "abdikace"

        let result = RecoveryPhraseValidator.validate(words: words, standard: .electrum)

        #expect(result.status == .unknownWords)
        #expect(result.unknownWordPositions == [0])
    }

    @Test
    func normalize_matchesElectrum() {
        // Expected values computed with `normalize_text` from `electrum/mnemonic.py`.
        #expect(ElectrumSeedVersion.normalize("  OStrich  SECURITY\tdeer ") == "ostrich security deer")
        #expect(ElectrumSeedVersion.normalize("almíbar peatón") == "almibar peaton")
        #expect(ElectrumSeedVersion.normalize("眼 悲 叛") == "眼悲叛")
        #expect(ElectrumSeedVersion.normalize("なのか\u{3000}まなぶ") == "なのかまなふ")
        #expect(ElectrumSeedVersion.normalize("abc 眼 def") == "abc 眼 def")
    }

    // MARK: - Monero

    @Test(arguments: RecoveryPhraseTestVectors.moneroValid)
    func validate_moneroValidSeeds(phrase: String) {
        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .monero)

        #expect(result.status == .valid(.monero))
    }

    @Test
    func validate_moneroUnknownWord() throws {
        var words = try RecoveryPhraseInput.words(in: #require(RecoveryPhraseTestVectors.moneroValid.first))
        words[3] = "abandon" // BIP39, but not Monero

        let result = RecoveryPhraseValidator.validate(words: words, standard: .monero)

        #expect(result.status == .unknownWords)
        #expect(result.unknownWordPositions == [3])
    }

    @Test(arguments: RecoveryPhraseTestVectors.moneroValid)
    func validate_moneroSwappedWordsHaveInvalidChecksum(phrase: String) {
        var words = RecoveryPhraseInput.words(in: phrase)
        // Reordering the words changes which word the checksum selects. (Checked against Monero's algorithm to
        // not select a word with the same prefix by chance, which would still be valid, for these seeds.)
        words.swapAt(0, 1)

        let result = RecoveryPhraseValidator.validate(words: words, standard: .monero)

        #expect(result.status == .invalidChecksum)
    }

    /// Monero matches words by their unique three letter prefix, so abbreviations and anything after the prefix
    /// don't matter, as in `find_seed_language`.
    @Test(arguments: RecoveryPhraseTestVectors.moneroValid)
    func validate_moneroMatchesWordsByPrefix(phrase: String) {
        let words = RecoveryPhraseInput.words(in: phrase)
        let abbreviated = words.enumerated().map { offset, word in
            offset.isMultiple(of: 2) ? String(word.prefix(3)) : word + "xyz"
        }

        let result = RecoveryPhraseValidator.validate(words: abbreviated, standard: .monero)

        #expect(result.status == .valid(.monero))
        #expect(result.canonicalWords == words, "Saved with the whole words")
    }

    /// Passes the checksum, but the first three words would need more than 32 bits, so Monero's `words_to_bytes`
    /// rejects it ("mumble mumble"). Built, and checked, with Monero's algorithm.
    @Test
    func validate_moneroGroupThatOverflowsIsMalformed() {
        let phrase = "velvet abducts abbey number token physics poetry unquoted nibs useful sabotage limits benches "
            + "lifestyle eden nitrogen anvil fewest avoid batch vials washing fences goat abducts"

        let result = RecoveryPhraseValidator.validate(words: RecoveryPhraseInput.words(in: phrase), standard: .monero)

        #expect(result.status == .malformed)
    }

    @Test(arguments: RecoveryPhraseTestVectors.moneroValid)
    func validate_moneroWrongChecksumWord(phrase: String) {
        var words = RecoveryPhraseInput.words(in: phrase)
        words[24] = words[24] == "abbey" ? "zoom" : "abbey"

        let result = RecoveryPhraseValidator.validate(words: words, standard: .monero)

        #expect(result.status == .invalidChecksum)
    }

    // MARK: - Other

    @Test
    func validate_otherIsNeverValidated() {
        let result = RecoveryPhraseValidator.validate(words: ["any", "words", "at", "all"], standard: .other)

        #expect(result.status == .notValidated)
        #expect(result.isValid == false)
    }

    @Test
    func validate_otherStillReportsMissingWords() {
        let result = RecoveryPhraseValidator.validate(words: ["any", " ", "words"], standard: .other)

        #expect(result.status == .notValidated)
        #expect(result.missingWordPositions == [1])
    }
}

struct RecoveryPhraseChecksumTests {
    @Test
    func crc32_matchesCheckValue() {
        #expect(CRC32.checksum("123456789".utf8) == 0xCBF4_3926)
        #expect(CRC32.checksum([UInt8]()) == 0)
    }

    @Test
    func bip39Checksum_rejectsCountsThatAreNotAMultipleOfThree() {
        #expect(BIP39Checksum.isValid(indices: []) == false)
        #expect(BIP39Checksum.isValid(indices: Array(repeating: 0, count: 13)) == false)
    }
}

private let validTwelveWords = Array(repeating: "abandon", count: 11) + ["about"]
