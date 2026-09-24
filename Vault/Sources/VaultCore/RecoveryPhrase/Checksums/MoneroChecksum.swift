import Foundation

/// The checksum word at the end of a Monero seed.
///
/// The CRC-32 of the concatenated unique prefixes of every other word selects which of those words is repeated as the
/// final, checksum, word. Mirrors `create_checksum_index` and `checksum_test` in
/// `monero-project/monero` `src/mnemonics/electrum-words.cpp`.
enum MoneroChecksum {
    /// The number of leading characters that uniquely identify a word in the English list.
    static let uniquePrefixLength = 3

    /// - Parameter words: The words of the seed, including the final checksum word, as spelled in the wordlist.
    static func isValid(words: [String]) -> Bool {
        guard let checksumWord = words.last, words.count > 1 else { return false }
        let seedWords = words.dropLast()
        let trimmed = seedWords.map(uniquePrefix(of:)).joined()
        let index = Int(CRC32.checksum(trimmed.utf8) % UInt32(seedWords.count))
        return uniquePrefix(of: seedWords[index]) == uniquePrefix(of: checksumWord)
    }

    private static func uniquePrefix(of word: String) -> String {
        var prefix = String.UnicodeScalarView()
        prefix.append(contentsOf: word.unicodeScalars.prefix(uniquePrefixLength))
        return String(prefix)
    }
}
