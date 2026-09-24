import Foundation

/// A standard that defines the format of a recovery phrase: the wordlist(s) it uses, how many words it has and how
/// its checksum is computed.
public enum RecoveryPhraseStandard: Equatable, Hashable, CaseIterable, Sendable {
    /// BIP39 mnemonic, as used by most wallets. Any of the official wordlists.
    case bip39
    /// SLIP-39 Shamir share, as used by Trezor. A single share of a (possibly) multi-share backup.
    case slip39
    /// Electrum "new style" (v2) seed.
    case electrum
    /// Monero 25 word seed, English wordlist.
    case monero
    /// Any other list of words. No validation is performed.
    case other
}

extension RecoveryPhraseStandard {
    /// The range of word counts allowed for a phrase that isn't validated against a standard.
    public static let otherWordCountRange: ClosedRange<Int> = 1 ... 48

    /// The word counts that are valid for this standard, in ascending order.
    public var supportedWordCounts: [Int] {
        switch self {
        case .bip39: [12, 15, 18, 21, 24]
        case .slip39: [20, 33]
        // 12 and 13 words for current and early 2.x seeds, 24 and 25 for pre-2.7 2FA seeds.
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
}
