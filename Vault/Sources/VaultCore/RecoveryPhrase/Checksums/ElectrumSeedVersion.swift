import CryptoKit
import Foundation
import FoundationExtensions

/// The kind of wallet an Electrum seed creates.
public enum ElectrumSeedType: Equatable, Hashable, CaseIterable, Sendable {
    case standard
    case segwit
    case twoFactor
    case twoFactorSegwit
}

/// Validation of Electrum "new style" (v2) seeds.
///
/// Specification: the Electrum Seed Version System, https://electrum.readthedocs.io/en/latest/seedphrase.html.
/// These seeds don't depend on a wordlist and have no BIP39 style checksum. Instead, "a seed phrase must produce a
/// registered version number": the hex HMAC-SHA512 of the normalized phrase, keyed with "Seed version", starts with
/// a prefix identifying the seed type.
///
/// Ported from https://github.com/spesmilo/electrum/blob/master/electrum/mnemonic.py (`normalize_text`,
/// `is_new_seed`, `calc_seed_type`) and https://github.com/spesmilo/electrum/blob/master/electrum/version.py (the
/// prefixes), at commit `638fbba8ff0c449b773f2fe3d3d06b984491e8fa`. MIT licensed.
///
/// Old (pre 2.0) Electrum seeds, which use a different wordlist and encoding, aren't supported.
enum ElectrumSeedVersion {
    /// The registered version number, from `version.py`: `01` standard, `100` segwit, `101` 2FA and `102` 2FA segwit.
    static func seedType(of words: [String]) -> ElectrumSeedType? {
        let normalized = normalize(words.joined(separator: " "))
        let code = HMAC<SHA512>.authenticationCode(
            for: Data(normalized.utf8),
            using: SymmetricKey(data: Data("Seed version".utf8)),
        )
        let hexPrefix = code.prefix(2).map { String(format: "%02x", $0) }.joined()
        if hexPrefix.hasPrefix("01") {
            return .standard
        } else if hexPrefix.hasPrefix("100") {
            return .segwit
        } else if hexPrefix.hasPrefix("101"), words.count == 12 || words.count >= 20 {
            // Electrum reuses this prefix for 2FA seeds from before 2.7, which it tells apart by word count.
            return .twoFactor
        } else if hexPrefix.hasPrefix("102") {
            return .twoFactorSegwit
        } else {
            return nil
        }
    }

    /// Port of `normalize_text`, the documentation's `prepare_seed`, which "removes all but one space between words.
    /// It also removes diacritics, and it removes spaces between Asian CJK characters." Works on Unicode scalars, as
    /// Python strings are sequences of code points.
    static func normalize(_ text: String) -> String {
        let decomposed = text.decomposedStringWithCompatibilityMapping.lowercased()

        // Remove accents, and collapse whitespace to single spaces (`' '.join(seed.split())`).
        var scalars = [Unicode.Scalar]()
        var hasPendingSpace = false
        for scalar in decomposed.unicodeScalars where scalar.properties.canonicalCombiningClass == .notReordered {
            if scalar.properties.isWhitespace {
                hasPendingSpace = scalars.isNotEmpty
            } else {
                if hasPendingSpace {
                    scalars.append(" ")
                    hasPendingSpace = false
                }
                scalars.append(scalar)
            }
        }

        // Remove whitespace between CJK characters.
        var result = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated() {
            let isSpaceBetweenCJK = scalar == " "
                && index > 0
                && index < scalars.count - 1
                && isCJK(scalars[index - 1])
                && isCJK(scalars[index + 1])
            if !isSpaceBetweenCJK {
                result.append(scalar)
            }
        }
        return String(result)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        cjkIntervals.contains { $0.contains(scalar.value) }
    }

    /// `CJK_INTERVALS`, verbatim.
    private static let cjkIntervals: [ClosedRange<UInt32>] = [
        0x4E00 ... 0x9FFF, // CJK Unified Ideographs
        0x3400 ... 0x4DBF, // CJK Unified Ideographs Extension A
        0x20000 ... 0x2A6DF, // CJK Unified Ideographs Extension B
        0x2A700 ... 0x2B73F, // CJK Unified Ideographs Extension C
        0x2B740 ... 0x2B81F, // CJK Unified Ideographs Extension D
        0xF900 ... 0xFAFF, // CJK Compatibility Ideographs
        0x2F800 ... 0x2FA1D, // CJK Compatibility Ideographs Supplement
        0x3190 ... 0x319F, // Kanbun
        0x2E80 ... 0x2EFF, // CJK Radicals Supplement
        0x2F00 ... 0x2FDF, // CJK Radicals
        0x31C0 ... 0x31EF, // CJK Strokes
        0x2FF0 ... 0x2FFF, // Ideographic Description Characters
        0xE0100 ... 0xE01EF, // Variation Selectors Supplement
        0x3100 ... 0x312F, // Bopomofo
        0x31A0 ... 0x31BF, // Bopomofo Extended
        0xFF00 ... 0xFFEF, // Halfwidth and Fullwidth Forms
        0x3040 ... 0x309F, // Hiragana
        0x30A0 ... 0x30FF, // Katakana
        0x31F0 ... 0x31FF, // Katakana Phonetic Extensions
        0x1B000 ... 0x1B0FF, // Kana Supplement
        0xAC00 ... 0xD7AF, // Hangul Syllables
        0x1100 ... 0x11FF, // Hangul Jamo
        0xA960 ... 0xA97F, // Hangul Jamo Extended A
        0xD7B0 ... 0xD7FF, // Hangul Jamo Extended B
        0x3130 ... 0x318F, // Hangul Compatibility Jamo
        0xA4D0 ... 0xA4FF, // Lisu
        0x16F00 ... 0x16F9F, // Miao
        0xA000 ... 0xA48F, // Yi Syllables
        0xA490 ... 0xA4CF, // Yi Radicals
    ]
}
