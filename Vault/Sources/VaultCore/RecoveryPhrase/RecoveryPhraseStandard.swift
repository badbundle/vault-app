import Foundation

/// A standard that defines the format of a recovery phrase: the wordlist(s) it uses, how many words it has and how
/// its checksum is computed.
public enum RecoveryPhraseStandard: Equatable, Hashable, CaseIterable, Sendable {
    /// BIP39 mnemonic, as used by most wallets, with any of the official wordlists.
    ///
    /// https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
    case bip39
    /// SLIP-39 Shamir share, as used by Trezor. A single share of a (possibly) multi-share backup.
    ///
    /// https://github.com/satoshilabs/slips/blob/master/slip-0039.md
    case slip39
    /// Electrum "new style" (version 2.0 and later) seed.
    ///
    /// https://electrum.readthedocs.io/en/latest/seedphrase.html
    case electrum
    /// Monero seed, with the English wordlist.
    ///
    /// https://www.getmonero.org/resources/moneropedia/mnemonicseed.html
    case monero
    /// Any other list of words. No validation is performed.
    case other
}

extension RecoveryPhraseStandard {
    /// The range of word counts allowed for a phrase that isn't validated against a standard.
    public static let otherWordCountRange: ClosedRange<Int> = 1 ... 48

    /// The word counts that are valid for this standard, in ascending order.
    ///
    /// - BIP39: 128 to 256 bits of entropy, in steps of 32, plus the checksum ("Generating the mnemonic").
    /// - SLIP-39: the specification allows any master secret that's a multiple of 16 bits and at least 128 bits, but
    ///   "all implementations MUST support master secrets of length 128 bits and 256 bits", which are the 20 and 33
    ///   word shares wallets create. Shares of other lengths can be stored as `other`.
    /// - Electrum: the version number doesn't depend on the length. Electrum creates 12 word seeds (13 in some 2.x
    ///   versions), and 24 or 25 word 2FA seeds before 2.7 (see `calc_seed_type` in `electrum/mnemonic.py`).
    /// - Monero: 24 words for the 256 bit key, plus the checksum word. The legacy 13 word MyMonero and 16 word Polyseed
    ///   formats can be stored as `other`.
    public var supportedWordCounts: [Int] {
        switch self {
        case .bip39: [12, 15, 18, 21, 24]
        case .slip39: [20, 33]
        case .electrum: [12, 13, 24, 25]
        case .monero: [25]
        case .other: Array(Self.otherWordCountRange)
        }
    }

    /// The word count that a new phrase of this standard starts with.
    public var defaultWordCount: Int {
        switch self {
        case .bip39: 24
        case .slip39: 20
        case .electrum: 12
        case .monero: 25
        case .other: 24
        }
    }

    /// If the words and checksum of this standard can be validated.
    public var isValidated: Bool {
        switch self {
        case .bip39, .slip39, .electrum, .monero: true
        case .other: false
        }
    }

    public func supports(wordCount: Int) -> Bool {
        supportedWordCounts.contains(wordCount)
    }

    /// The supported word count that is closest to `wordCount`, preferring the larger count on a tie.
    public func nearestSupportedWordCount(to wordCount: Int) -> Int {
        supportedWordCounts.min { lhs, rhs in
            let lhsDistance = abs(lhs - wordCount)
            let rhsDistance = abs(rhs - wordCount)
            return lhsDistance == rhsDistance ? lhs > rhs : lhsDistance < rhsDistance
        } ?? defaultWordCount
    }

    /// If `passphrase` is allowed by this standard.
    ///
    /// SLIP-39: "the passphrase MUST be a string containing only printable ASCII characters (code points 32-126)"
    /// ("Passphrase" section). BIP39 allows any text, normalized to NFKD ("From mnemonic to seed"), as do Electrum and
    /// Monero.
    public func allowsPassphrase(_ passphrase: String) -> Bool {
        switch self {
        case .slip39: passphrase.unicodeScalars.allSatisfy { (32 ... 126).contains($0.value) }
        case .bip39, .electrum, .monero, .other: true
        }
    }
}
