import CryptoKit
import Foundation
import Testing
@testable import VaultCore

struct RecoveryPhraseWordlistTests {
    @Test(arguments: RecoveryPhraseWordlist.ID.all)
    func named_loadsExpectedNumberOfWords(id: RecoveryPhraseWordlist.ID) throws {
        let wordlist = try #require(RecoveryPhraseWordlist.named(id))

        #expect(wordlist.words.count == id.expectedWordCount)
        #expect(Set(wordlist.words).count == id.expectedWordCount)
    }

    @Test(arguments: RecoveryPhraseWordlist.ID.all)
    func indexOf_everyWordMapsBackToItsOwnIndex(id: RecoveryPhraseWordlist.ID) throws {
        let wordlist = try #require(RecoveryPhraseWordlist.named(id))

        // Also proves that no two words collide once normalized (and diacritics are folded).
        for (index, word) in wordlist.words.enumerated() {
            #expect(wordlist.index(of: word) == index)
        }
    }

    /// Pins the bundled files to the exact upstream content documented on `RecoveryPhraseWordlist`.
    @Test(arguments: [
        (.bip39(.english), "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"),
        (.bip39(.japanese), "2eed0aef492291e061633d7ad8117f1a2b03eb80a29d0e4e3117ac2528d05ffd"),
        (.bip39(.korean), "9e95f86c167de88f450f0aaf89e87f6624a57f973c67b516e338e8e8b8897f60"),
        (.bip39(.spanish), "46846a5a0139d1e3cb77293e521c2865f7bcdb82c44e8d0a06a2cd0ecba48c0b"),
        (.bip39(.chineseSimplified), "5c5942792bd8340cb8b27cd592f1015edf56a8c5b26276ee18a482428e7c5726"),
        (.bip39(.chineseTraditional), "417b26b3d8500a4ae3d59717d7011952db6fc2fb84b807f3f94ac734e89c1b5f"),
        (.bip39(.french), "ebc3959ab7801a1df6bac4fa7d970652f1df76b683cd2f4003c941c63d517e59"),
        (.bip39(.italian), "d392c49fdb700a24cd1fceb237c1f65dcc128f6b34a8aacb58b59384b5c648c2"),
        (.bip39(.czech), "7e80e161c3e93d9554c2efb78d4e3cebf8fc727e9c52e03b83b94406bdcc95fc"),
        (.bip39(.portuguese), "2685e9c194c82ae67e10ba59d9ea5345a23dc093e92276fc5361f6667d79cd3f"),
        (.slip39, "bcc4555340332d169718aed8bf31dd9d5248cb7da6e5d355140ef4f1e601eec3"),
        (.monero, "eaa6bce7dd92f4d6dd74f224264e0ef4ad21095d68ec77616b26ceb599baf4f7"),
    ] as [(RecoveryPhraseWordlist.ID, String)])
    func bundledFile_matchesPinnedHash(id: RecoveryPhraseWordlist.ID, expectedSHA256: String) throws {
        let url = try #require(RecoveryPhraseWordlist.bundledFileURL(for: id))
        let data = try Data(contentsOf: url)

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hash == expectedSHA256)
    }

    @Test(arguments: [
        ("abandon", 0),
        ("ABANDON", 0),
        ("  Abandon\n", 0),
        ("ａｂａｎｄｏｎ", 0), // full-width
        ("zoo", 2047),
    ])
    func indexOf_englishIgnoresCaseWhitespaceAndWidth(word: String, expected: Int) throws {
        let wordlist = try #require(RecoveryPhraseWordlist.named(.bip39(.english)))

        #expect(wordlist.index(of: word) == expected)
    }

    @Test
    func indexOf_unknownWordIsNil() throws {
        let wordlist = try #require(RecoveryPhraseWordlist.named(.bip39(.english)))

        #expect(wordlist.index(of: "abandonn") == nil)
        #expect(wordlist.index(of: "") == nil)
    }

    @Test
    func indexOf_latinListsIgnoreDiacritics() throws {
        let spanish = try #require(RecoveryPhraseWordlist.named(.bip39(.spanish)))
        let french = try #require(RecoveryPhraseWordlist.named(.bip39(.french)))

        let arbol = try #require(spanish.index(of: "árbol"))
        #expect(spanish.index(of: "arbol") == arbol)
        #expect(spanish.words[arbol] == "árbol")
        // Precomposed input matches the decomposed spelling in the file.
        let academie = try #require(french.index(of: "acad\u{E9}mie"))
        #expect(french.index(of: "academie") == academie)
        #expect(french.words[academie] == "académie")
    }

    @Test
    func indexOf_moneroMatchesUniquePrefix() throws {
        let monero = try #require(RecoveryPhraseWordlist.named(.monero))
        let velvet = try #require(monero.index(of: "velvet"))

        #expect(monero.index(of: "vel") == velvet)
        #expect(monero.index(of: "VELVETT") == velvet)
        #expect(monero.index(of: "ve") == nil, "Shorter than the unique prefix")
        #expect(monero.index(of: "xyz") == nil)
    }

    @Test(arguments: [RecoveryPhraseWordlist.ID.bip39(.english), .slip39])
    func indexOf_bip39AndSLIP39OnlyMatchWholeWords(id: RecoveryPhraseWordlist.ID) throws {
        let wordlist = try #require(RecoveryPhraseWordlist.named(id))
        let word = try #require(wordlist.words.first { $0.count > 4 })

        #expect(wordlist.index(of: String(word.prefix(4))) == nil)
        #expect(wordlist.index(of: word + "x") == nil)
    }

    @Test
    func uniquePrefixes_areUniqueWhereMatchedByPrefix() throws {
        let monero = try #require(RecoveryPhraseWordlist.named(.monero))

        #expect(Set(monero.words.map { $0.prefix(3) }).count == monero.words.count)
    }

    @Test
    func indexOf_japaneseKeepsVoicingMarks() throws {
        let japanese = try #require(RecoveryPhraseWordlist.named(.bip39(.japanese)))

        #expect(japanese.index(of: "がっこう") != nil)
        // Without the voicing mark, it's a different (non-existent) word.
        #expect(japanese.index(of: "かっこう") == nil)
    }

    @Test
    func completions_returnsWordsWithPrefixInAlphabeticalOrder() throws {
        let english = try #require(RecoveryPhraseWordlist.named(.bip39(.english)))

        #expect(english.completions(forPrefix: "ab", limit: 3) == ["abandon", "ability", "able"])
        #expect(english.completions(forPrefix: "zoo", limit: 3) == ["zoo"])
        #expect(english.completions(forPrefix: "ZO", limit: 5) == ["zone", "zoo"])
    }

    @Test
    func completions_emptyForBlankPrefixOrNoMatches() throws {
        let english = try #require(RecoveryPhraseWordlist.named(.bip39(.english)))

        #expect(english.completions(forPrefix: "", limit: 3).isEmpty)
        #expect(english.completions(forPrefix: "  ", limit: 3).isEmpty)
        #expect(english.completions(forPrefix: "xyz", limit: 3).isEmpty)
        #expect(english.completions(forPrefix: "ab", limit: 0).isEmpty)
    }

    @Test
    func completions_matchesWithoutDiacritics() throws {
        let spanish = try #require(RecoveryPhraseWordlist.named(.bip39(.spanish)))

        #expect(spanish.completions(forPrefix: "arbo", limit: 3) == ["árbol"])
    }

    @Test
    func completions_matchesPartiallyComposedHangulSyllable() throws {
        let korean = try #require(RecoveryPhraseWordlist.named(.bip39(.korean)))

        // "가" is a prefix of words beginning "각" once decomposed into jamo.
        let completions = korean.completions(forPrefix: "가", limit: 50)
        #expect(completions.contains("각자"))
    }
}
