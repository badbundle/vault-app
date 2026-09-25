import Foundation
import FoundationExtensions

/// The result of checking a recovery phrase against its standard.
public struct RecoveryPhraseValidation: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// The standard doesn't define a wordlist or checksum, or the wordlist couldn't be loaded.
        case notValidated
        /// Some words haven't been entered yet.
        case incomplete
        /// The standard doesn't allow a phrase of this many words.
        case unsupportedWordCount
        /// Some words aren't in the wordlist.
        case unknownWords
        /// Every word is in the wordlist, but the checksum doesn't match (or, for Electrum, there's no registered
        /// version number). A word was mistyped as another valid word, or the words are in the wrong order.
        case invalidChecksum
        /// The checksum matches, but the words don't encode something the standard allows: a SLIP-39 share with
        /// non-zero padding or a group threshold above the group count, or a Monero seed that doesn't decode to a key.
        case malformed
        case valid(Detail)
    }

    public enum Detail: Equatable, Sendable {
        /// Valid in each of these languages (almost always just one: the Chinese lists share many characters).
        case bip39(languages: [BIP39Language])
        case slip39(isExtendable: Bool)
        case electrum(ElectrumSeedType)
        case monero
    }

    public var status: Status
    /// Zero-based positions of words that aren't blank, but aren't in the wordlist.
    public var unknownWordPositions: [Int]
    /// Zero-based positions of words that are blank.
    public var missingWordPositions: [Int]
    /// When valid, the words as spelled in the wordlist (for example with accents that were omitted when entered).
    public var canonicalWords: [String]?

    public init(
        status: Status,
        unknownWordPositions: [Int] = [],
        missingWordPositions: [Int] = [],
        canonicalWords: [String]? = nil,
    ) {
        self.status = status
        self.unknownWordPositions = unknownWordPositions
        self.missingWordPositions = missingWordPositions
        self.canonicalWords = canonicalWords
    }

    public var isValid: Bool {
        if case .valid = status {
            true
        } else {
            false
        }
    }
}

/// Checks the words of a recovery phrase against the wordlist and checksum of a standard.
///
/// This only ever informs: BIP39 says that for a mnemonic that doesn't validate, "software must compute a checksum
/// for the mnemonic sentence using a wordlist and issue a warning if it is invalid"
/// (https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki, "From mnemonic to seed"), and SLIP-39 that
/// implementations SHOULD NOT correct errors "beyond potentially suggesting to the user where in the mnemonic an
/// error might be found, without suggesting the correction to make"
/// (https://github.com/satoshilabs/slips/blob/master/slip-0039.md, "Combining the shares").
public enum RecoveryPhraseValidator {
    public static func validate(words: [String], standard: RecoveryPhraseStandard) -> RecoveryPhraseValidation {
        let words = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let missing = words.indices.filter { words[$0].isEmpty }

        let wordlistIDs: [RecoveryPhraseWordlist.ID] = switch standard {
        case .bip39: BIP39Language.allCases.map { .bip39($0) }
        // Electrum can create seeds using these lists (`electrum/mnemonic.py` `filenames`).
        case .electrum: [.english, .spanish, .japanese, .portuguese, .chineseSimplified].map { .bip39($0) }
        case .slip39: [.slip39]
        case .monero: [.monero]
        case .other: []
        }
        let wordlists = wordlistIDs.compactMap(RecoveryPhraseWordlist.named)
        guard standard.isValidated, wordlists.isNotEmpty else {
            return .init(status: .notValidated, missingWordPositions: missing)
        }

        let matches = wordlists.map { WordlistMatch(wordlist: $0, words: words) }
        guard let bestMatch = bestMatch(in: matches) else {
            return .init(status: .notValidated, missingWordPositions: missing)
        }
        let unknown = words.indices.filter { words[$0].isNotEmpty && bestMatch.indices[$0] == nil }

        func result(
            _ status: RecoveryPhraseValidation.Status,
            canonicalWords: [String]? = nil,
        ) -> RecoveryPhraseValidation {
            .init(
                status: status,
                unknownWordPositions: unknown,
                missingWordPositions: missing,
                canonicalWords: canonicalWords,
            )
        }

        guard standard.supports(wordCount: words.count) else { return result(.unsupportedWordCount) }
        // Electrum seeds don't depend on a wordlist: "a seed phrase must produce a registered version number", so a
        // seed that does is valid even with words that aren't in any list Electrum ships.
        if standard == .electrum, missing.isEmpty, let seedType = ElectrumSeedVersion.seedType(of: words) {
            return .init(status: .valid(.electrum(seedType)), canonicalWords: bestMatch.canonicalWords)
        }
        guard unknown.isEmpty else { return result(.unknownWords) }
        guard missing.isEmpty else { return result(.incomplete) }

        switch standard {
        case .bip39:
            let valid = matches.filter { match in
                guard let indices = match.completeIndices else { return false }
                return BIP39Checksum.isValid(indices: indices)
            }
            guard let first = valid.first else { return result(.invalidChecksum) }
            let languages = valid.compactMap { match -> BIP39Language? in
                guard case let .bip39(language) = match.wordlist.id else { return nil }
                return language
            }
            return result(.valid(.bip39(languages: languages)), canonicalWords: first.canonicalWords)
        case .electrum:
            // Only reached when the version number isn't registered.
            return result(.invalidChecksum)
        case .slip39:
            guard let indices = bestMatch.completeIndices else { return result(.unknownWords) }
            switch SLIP39Share.validate(indices: indices) {
            case let .valid(isExtendable):
                return result(.valid(.slip39(isExtendable: isExtendable)), canonicalWords: bestMatch.canonicalWords)
            case .invalidChecksum:
                return result(.invalidChecksum)
            case .malformed:
                return result(.malformed)
            }
        case .monero:
            guard let indices = bestMatch.completeIndices else { return result(.unknownWords) }
            let canonicalWords = bestMatch.canonicalWords
            let wordlistCount = bestMatch.wordlist.words.count
            switch MoneroSeed.validate(indices: indices, words: canonicalWords, wordlistCount: wordlistCount) {
            case .valid:
                return result(.valid(.monero), canonicalWords: canonicalWords)
            case .invalidChecksum:
                return result(.invalidChecksum)
            case .malformed:
                return result(.malformed)
            }
        case .other:
            return result(.notValidated)
        }
    }

    /// The list that the most words were found in. On a tie, the earliest list wins, so English is preferred for
    /// the words it shares with French.
    private static func bestMatch(in matches: [WordlistMatch]) -> WordlistMatch? {
        matches.enumerated().max { lhs, rhs in
            lhs.element.matchedCount == rhs.element.matchedCount
                ? lhs.offset > rhs.offset
                : lhs.element.matchedCount < rhs.element.matchedCount
        }?.element
    }
}

/// The words of a phrase looked up in a single wordlist.
private struct WordlistMatch {
    let wordlist: RecoveryPhraseWordlist
    let indices: [Int?]
    let words: [String]

    init(wordlist: RecoveryPhraseWordlist, words: [String]) {
        self.wordlist = wordlist
        self.words = words
        indices = words.map { $0.isEmpty ? nil : wordlist.index(of: $0) }
    }

    var matchedCount: Int {
        indices.count { $0 != nil }
    }

    /// The index of every word, if all of them are in the list.
    var completeIndices: [Int]? {
        let found = indices.compactMap(\.self)
        return found.count == indices.count ? found : nil
    }

    /// The words as spelled in the list, keeping any that aren't in it as they were entered.
    var canonicalWords: [String] {
        zip(indices, words).map { index, word in index.map { wordlist.words[$0] } ?? word }
    }
}
