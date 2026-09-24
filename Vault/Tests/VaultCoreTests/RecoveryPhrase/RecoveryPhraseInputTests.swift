import Foundation
import Testing
import VaultCore

struct RecoveryPhraseInputTests {
    @Test(arguments: [
        ("", []),
        ("   \n ", []),
        ("abandon", ["abandon"]),
        ("abandon ability able", ["abandon", "ability", "able"]),
        ("  abandon\n\tability   able ", ["abandon", "ability", "able"]),
        ("abandon,ability, able;about", ["abandon", "ability", "able", "about"]),
        ("abandon\u{00A0}ability", ["abandon", "ability"]), // no-break space
        ("aban\u{200B}don", ["abandon"]), // zero-width space
        ("\u{FEFF}abandon", ["abandon"]), // byte order mark
    ])
    func words_splitsOnWhitespaceAndSeparators(text: String, expected: [String]) {
        #expect(RecoveryPhraseInput.words(in: text) == expected)
    }

    @Test(arguments: [
        ("1. abandon 2. ability 3. able", ["abandon", "ability", "able"]),
        ("1 abandon 2 ability", ["abandon", "ability"]),
        ("1) abandon 2) ability", ["abandon", "ability"]),
        ("1: abandon 2: ability", ["abandon", "ability"]),
        ("01 abandon 02 ability", ["abandon", "ability"]),
        ("1.abandon 2.ability", ["abandon", "ability"]),
        ("1)abandon", ["abandon"]),
        ("１．abandon", ["abandon"]), // full-width numbering
        ("1abandon", ["1abandon"]), // not numbering
    ])
    func words_removesNumbering(text: String, expected: [String]) {
        #expect(RecoveryPhraseInput.words(in: text) == expected)
    }

    @Test
    func words_splitsOnIdeographicSpace() {
        let text = "あいこくしん\u{3000}あいさつ\u{3000}あいだ"

        #expect(RecoveryPhraseInput.words(in: text) == ["あいこくしん", "あいさつ", "あいだ"])
    }

    @Test
    func words_splitsRunsOfChineseCharactersIntoSingleWords() {
        #expect(RecoveryPhraseInput.words(in: "的一是") == ["的", "一", "是"])
        #expect(RecoveryPhraseInput.words(in: "的 一，是、在") == ["的", "一", "是", "在"])
    }

    @Test(arguments: [
        ("abandon", false),
        ("", false),
        ("日本", false),
        ("abandon ", true),
        (" abandon", true),
        ("aban don", true),
        ("abandon\n", true),
        ("abandon,", true),
        ("abandon;", true),
        ("あいこくしん\u{3000}", true),
        ("的、", true),
    ])
    func containsSeparator(text: String, expected: Bool) {
        #expect(RecoveryPhraseInput.containsSeparator(text) == expected)
    }

    @Test
    func words_doesNotSplitKana() {
        #expect(RecoveryPhraseInput.words(in: "がっこう") == ["がっこう"])
    }
}
