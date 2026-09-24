import Foundation
import Testing
import VaultCore

struct RecoveryPhraseTests {
    @Test
    func description_isRedacted() {
        let sut = RecoveryPhrase(
            title: "My title",
            words: ["abandon", "ability", "able"],
            standard: .bip39,
            passphrase: "secret",
            contents: "private contents",
        )

        let representations = [
            String(describing: sut),
            String(reflecting: sut),
            "\(sut)",
            String(describing: [sut]),
            String(describing: Optional(sut) as Any),
        ]
        for representation in representations {
            #expect(!representation.contains("abandon"))
            #expect(!representation.contains("secret"))
            #expect(!representation.contains("private contents"))
            #expect(representation.contains("3 words"))
        }
    }

    @Test
    func mirror_doesNotExposeWords() {
        let sut = RecoveryPhrase(
            title: "",
            words: ["abandon"],
            standard: .bip39,
            passphrase: "secret",
            contents: "private contents",
        )

        let children = Mirror(reflecting: sut).children.map { "\($0.label ?? ""): \($0.value)" }

        #expect(children == ["wordCount: 1"])
    }
}

struct RecoveryPhraseStandardTests {
    @Test(arguments: RecoveryPhraseStandard.allCases)
    func defaultWordCount_isSupported(standard: RecoveryPhraseStandard) {
        #expect(standard.supports(wordCount: standard.defaultWordCount))
    }

    @Test
    func supportedWordCounts() {
        #expect(RecoveryPhraseStandard.bip39.supportedWordCounts == [12, 15, 18, 21, 24])
        #expect(RecoveryPhraseStandard.slip39.supportedWordCounts == [20, 33])
        #expect(RecoveryPhraseStandard.electrum.supportedWordCounts == [12, 13, 24, 25])
        #expect(RecoveryPhraseStandard.monero.supportedWordCounts == [25])
        #expect(RecoveryPhraseStandard.other.supportedWordCounts == Array(1 ... 48))
    }

    @Test(arguments: [
        (RecoveryPhraseStandard.bip39, 25, 24),
        (.bip39, 13, 12),
        (.bip39, 14, 15),
        (.bip39, 1, 12),
        (.slip39, 24, 20),
        (.slip39, 27, 33),
        (.monero, 12, 25),
        (.other, 25, 25),
        (.other, 60, 48),
    ])
    func nearestSupportedWordCount(standard: RecoveryPhraseStandard, wordCount: Int, expected: Int) {
        #expect(standard.nearestSupportedWordCount(to: wordCount) == expected)
    }
}
