import Foundation
import FoundationExtensions

/// Splits free-form text, typically pasted, into the individual words of a recovery phrase.
public enum RecoveryPhraseInput {
    /// The words in `text`, in order.
    ///
    /// Tolerates the ways phrases are commonly written down or exported:
    /// - separated by any whitespace (including the ideographic space used for Japanese) or by commas/semicolons;
    /// - numbered, like `1. abandon 2. ability` or `1)abandon`, where the numbering is dropped;
    /// - Chinese words run together without spaces, where each character is a separate word.
    public static func words(in text: String) -> [String] {
        var cleaned = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !invisibleScalars.contains(scalar) {
            cleaned.append(scalar)
        }
        return String(cleaned)
            .split { $0.isWhitespace || separators.contains($0) }
            .flatMap { token -> [String] in
                // NFKC maps full-width digits and punctuation to ASCII, so numbering is recognized.
                let normalized = String(token).precomposedStringWithCompatibilityMapping
                guard let word = removingNumbering(from: normalized) else { return [] }
                return splittingIdeographs(word)
            }
    }

    /// If `text` contains anything that separates words, so is (or might be) more than a single word.
    public static func containsSeparator(_ text: String) -> Bool {
        text.contains { $0.isWhitespace || separators.contains($0) }
    }

    /// Zero-width characters that commonly sneak in when copying text.
    private static let invisibleScalars: Set<Unicode.Scalar> = ["\u{200B}", "\u{FEFF}"]

    private static let separators: Set<Character> = [",", ";", "、", "，", "；"]

    private static let numberingTerminators: Set<Character> = [".", ")", ":"]

    /// Removes a leading number from the token, returning `nil` if the token was only a number.
    private static func removingNumbering(from token: String) -> String? {
        let digits = token.prefix { $0.isASCII && $0.isNumber }
        guard digits.isNotEmpty else { return token }
        var remainder = token.dropFirst(digits.count)
        if let first = remainder.first {
            // Something like "12abc" isn't numbering, so leave it alone.
            guard numberingTerminators.contains(first) else { return token }
            remainder = remainder.dropFirst()
        }
        return remainder.isEmpty ? nil : String(remainder)
    }

    /// Chinese BIP39 words are a single character each, so a run of ideographs is several words.
    ///
    /// Kana are never split, as Japanese words are made up of several.
    private static func splittingIdeographs(_ word: String) -> [String] {
        guard word.count > 1, word.unicodeScalars.allSatisfy(\.properties.isIdeographic) else { return [word] }
        return word.map(String.init)
    }
}
