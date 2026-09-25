import Foundation
import FoundationExtensions

/// A list of words that the words of a recovery phrase are chosen from.
///
/// The index of a word within the list is the value it encodes, so the order is significant.
///
/// ## References
///
/// - BIP39 wordlists: https://github.com/bitcoin/bips/blob/master/bip-0039/bip-0039-wordlists.md, and the "Wordlist"
///   section of https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki (UTF-8, NFKD).
/// - SLIP-39 wordlist: https://github.com/satoshilabs/slips/blob/master/slip-0039/wordlist.txt, described in the
///   "Wordlist" section of https://github.com/satoshilabs/slips/blob/master/slip-0039.md.
/// - Monero English wordlist: https://github.com/monero-project/monero/blob/master/src/mnemonics/english.h (unique
///   prefix length 3).
///
/// ## Provenance
///
/// The lists are bundled as UTF-8 text files, one word per line, and are byte-for-byte copies of their upstream
/// sources. `RecoveryPhraseWordlistTests` pins the SHA-256 of every file so they can't change unnoticed.
///
/// - BIP39 (`bip39-*.txt`): `bitcoin/bips`, `bip-0039/*.txt` at commit `e8987d3e76d4501a0a5e6fd6c33c60b46c36479e`.
///   Identical to `src/mnemonic/wordlist/*.txt` in `trezor/python-mnemonic` at commit
///   `b57a5ad77a981e743f4167ab2f7927a55c1e82a8` (MIT).
/// - SLIP-39 (`slip39-english.txt`): `satoshilabs/slips`, `slip-0039/wordlist.txt` at commit
///   `570ed55b7fde158f1116be34fc2faa35dada5912`. Identical to `shamir_mnemonic/wordlist.txt` in
///   `trezor/python-shamir-mnemonic` at commit `17fcce14736afe498871d3018e4fa9330443471a` (MIT).
/// - Monero (`monero-english.txt`): `monero-project/monero`, `src/mnemonics/english.h` at commit
///   `d1bcbc76713be3905360d0d49f8cad0cd00d52e1` (BSD-3-Clause), with the quoted words extracted one per line.
///
/// Their licences are listed in the app's third-party libraries.
public struct RecoveryPhraseWordlist: Sendable {
    public let id: ID
    /// The words, in list order, in canonical (NFC) spelling.
    public let words: [String]
    private let indexByKey: [String: Int]
    /// For lists where a word is identified by its unique prefix alone, the index of each word by the lookup key of
    /// that prefix.
    private let indexByPrefixKey: [String: Int]
    /// Indexes into `words`, ordered by their lookup key, for prefix completions.
    private let indexesSortedByKey: [Int]
    private let keys: [String]

    init(id: ID, words: [String]) {
        self.id = id
        self.words = words.map(\.precomposedStringWithCanonicalMapping)
        let keys = words.map { Self.lookupKey(for: $0, foldingDiacritics: id.foldsDiacritics) }
        self.keys = keys
        indexByKey = Dictionary(keys.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        if let prefixLength = id.uniquePrefixLength {
            indexByPrefixKey = Dictionary(
                keys.enumerated().map { (Self.prefix(of: $1, length: prefixLength), $0) },
                uniquingKeysWith: { first, _ in first },
            )
        } else {
            indexByPrefixKey = [:]
        }
        indexesSortedByKey = keys.indices.sorted {
            keys[$0].unicodeScalars.lexicographicallyPrecedes(keys[$1].unicodeScalars)
        }
    }

    /// The index of `word` in this list, ignoring case, surrounding whitespace, Unicode normalization form and (for
    /// Latin-script lists) diacritics.
    ///
    /// For a list where words are identified by a unique prefix (Monero), any word starting with that prefix matches,
    /// as it does in Monero itself, so the abbreviation "vel" is "velvet".
    public func index(of word: String) -> Int? {
        let key = Self.lookupKey(for: word, foldingDiacritics: id.foldsDiacritics)
        if let index = indexByKey[key] {
            return index
        }
        guard let prefixLength = id.uniquePrefixLength, key.unicodeScalars.count >= prefixLength else { return nil }
        return indexByPrefixKey[Self.prefix(of: key, length: prefixLength)]
    }

    public func contains(_ word: String) -> Bool {
        index(of: word) != nil
    }

    /// Words from this list that start with `prefix`, in alphabetical order.
    public func completions(forPrefix prefix: String, limit: Int) -> [String] {
        let prefixKey = Self.lookupKey(for: prefix, foldingDiacritics: id.foldsDiacritics)
        guard prefixKey.isNotEmpty, limit > 0 else { return [] }
        // Compare scalars rather than characters, so a partially composed Hangul syllable or a kana without its
        // voicing mark is still a prefix of the complete word.
        let prefixScalars = Array(prefixKey.unicodeScalars)
        var completions = [String]()
        for index in indexesSortedByKey where keys[index].unicodeScalars.starts(with: prefixScalars) {
            completions.append(words[index])
            if completions.count == limit {
                break
            }
        }
        return completions
    }

    private static func prefix(of key: String, length: Int) -> String {
        var prefix = String.UnicodeScalarView()
        prefix.append(contentsOf: key.unicodeScalars.prefix(length))
        return String(prefix)
    }

    /// Normalizes a word so it can be matched against the words in a list.
    ///
    /// Compatibility decomposition (NFKD, https://unicode.org/reports/tr15/) matches the normalization BIP39 mandates
    /// for wordlists, and also maps full-width Latin characters to their ASCII equivalents.
    static func lookupKey(for word: String, foldingDiacritics: Bool) -> String {
        let decomposed = word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .decomposedStringWithCompatibilityMapping
            .lowercased()
        guard foldingDiacritics else { return decomposed }
        var folded = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars where scalar.properties.canonicalCombiningClass == .notReordered {
            folded.append(scalar)
        }
        return String(folded)
    }
}

// MARK: - Identifiers

extension RecoveryPhraseWordlist {
    public enum ID: Hashable, Sendable {
        case bip39(BIP39Language)
        case slip39
        case monero

        public static let all: [ID] = BIP39Language.allCases.map { .bip39($0) } + [.slip39, .monero]

        var resourceName: String {
            switch self {
            case let .bip39(language): "bip39-\(language.resourceSuffix)"
            case .slip39: "slip39-english"
            case .monero: "monero-english"
            }
        }

        public var expectedWordCount: Int {
            switch self {
            case .bip39: 2048
            case .slip39: 1024
            case .monero: 1626
            }
        }

        /// The number of leading characters that identify a word on their own, for lists that match words by it.
        ///
        /// Monero matches the words of a seed with a checksum word by this prefix (`find_seed_language` in
        /// https://github.com/monero-project/monero/blob/master/src/mnemonics/electrum-words.cpp), and the English
        /// list declares a prefix length of 3. The BIP39 and SLIP-39 lists also have unique 4 letter prefixes, but
        /// their reference implementations only accept whole words.
        var uniquePrefixLength: Int? {
            switch self {
            case .monero: 3
            case .bip39, .slip39: nil
            }
        }

        /// Whether diacritics are ignored when matching words.
        ///
        /// Only for Latin-script lists, where words are unique without their accents and people commonly type them
        /// without. The BIP39 wordlists document this for Spanish ("'ñ', 'ü', 'á', etc... are considered equal to
        /// 'n', 'u', 'a'") and French ("é-è" are considered equal to "e"); the Italian, Czech and Portuguese lists
        /// have no diacritics. Never for Japanese, where a voicing mark distinguishes different words.
        var foldsDiacritics: Bool {
            switch self {
            case let .bip39(language): language.isLatinScript
            case .slip39, .monero: true
            }
        }
    }
}

/// The languages that BIP39 has an official wordlist for.
public enum BIP39Language: Equatable, Hashable, CaseIterable, Sendable {
    case english
    case japanese
    case korean
    case spanish
    case chineseSimplified
    case chineseTraditional
    case french
    case italian
    case czech
    case portuguese

    /// BCP 47 identifier for the language, for display.
    public var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .japanese: "ja"
        case .korean: "ko"
        case .spanish: "es"
        case .chineseSimplified: "zh-Hans"
        case .chineseTraditional: "zh-Hant"
        case .french: "fr"
        case .italian: "it"
        case .czech: "cs"
        case .portuguese: "pt"
        }
    }

    fileprivate var resourceSuffix: String {
        switch self {
        case .english: "english"
        case .japanese: "japanese"
        case .korean: "korean"
        case .spanish: "spanish"
        case .chineseSimplified: "chinese_simplified"
        case .chineseTraditional: "chinese_traditional"
        case .french: "french"
        case .italian: "italian"
        case .czech: "czech"
        case .portuguese: "portuguese"
        }
    }

    fileprivate var isLatinScript: Bool {
        switch self {
        case .english, .spanish, .french, .italian, .czech, .portuguese: true
        case .japanese, .korean, .chineseSimplified, .chineseTraditional: false
        }
    }
}

// MARK: - Loading

extension RecoveryPhraseWordlist {
    /// The bundled wordlist for `id`, loaded on first use.
    ///
    /// `nil` if the list could not be loaded, in which case validation that depends on it is skipped.
    public static func named(_ id: ID) -> RecoveryPhraseWordlist? {
        switch id {
        case .bip39(.english): Cache.bip39English
        case .bip39(.japanese): Cache.bip39Japanese
        case .bip39(.korean): Cache.bip39Korean
        case .bip39(.spanish): Cache.bip39Spanish
        case .bip39(.chineseSimplified): Cache.bip39ChineseSimplified
        case .bip39(.chineseTraditional): Cache.bip39ChineseTraditional
        case .bip39(.french): Cache.bip39French
        case .bip39(.italian): Cache.bip39Italian
        case .bip39(.czech): Cache.bip39Czech
        case .bip39(.portuguese): Cache.bip39Portuguese
        case .slip39: Cache.slip39
        case .monero: Cache.monero
        }
    }

    /// Static lets are lazily initialized in a thread-safe way, so each list is only read from disk once, and only
    /// when it's first needed.
    private enum Cache {
        static let bip39English = load(.bip39(.english))
        static let bip39Japanese = load(.bip39(.japanese))
        static let bip39Korean = load(.bip39(.korean))
        static let bip39Spanish = load(.bip39(.spanish))
        static let bip39ChineseSimplified = load(.bip39(.chineseSimplified))
        static let bip39ChineseTraditional = load(.bip39(.chineseTraditional))
        static let bip39French = load(.bip39(.french))
        static let bip39Italian = load(.bip39(.italian))
        static let bip39Czech = load(.bip39(.czech))
        static let bip39Portuguese = load(.bip39(.portuguese))
        static let slip39 = load(.slip39)
        static let monero = load(.monero)
    }

    static func bundledFileURL(for id: ID) -> URL? {
        Bundle.module.url(forResource: id.resourceName, withExtension: "txt", subdirectory: "Wordlists")
    }

    private static func load(_ id: ID) -> RecoveryPhraseWordlist? {
        guard let url = bundledFileURL(for: id), let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let words = contents.split(separator: "\n").map(String.init)
        guard words.count == id.expectedWordCount else { return nil }
        return RecoveryPhraseWordlist(id: id, words: words)
    }
}
