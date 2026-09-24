import Foundation

/// Validation of a Monero 25 word seed.
///
/// Monero doesn't have a written specification for its seeds; the reference is its implementation:
/// https://github.com/monero-project/monero/blob/master/src/mnemonics/electrum-words.cpp (`words_to_bytes`,
/// `create_checksum_index` and `checksum_test`). See also
/// https://www.getmonero.org/resources/moneropedia/mnemonicseed.html.
///
/// The first 24 words encode the 256 bit private spend key, three words to each 32 bit chunk. The 25th word is a
/// checksum: it repeats one of the other words, chosen by the CRC-32 of their unique prefixes.
enum MoneroSeed {
    enum Result: Equatable {
        case valid
        case invalidChecksum
        /// The checksum matches, but a group of three words doesn't encode a 32 bit value, so Monero rejects the seed.
        case malformed
    }

    /// The number of leading characters that uniquely identify a word in the English list.
    static let uniquePrefixLength = 3

    /// - Parameters:
    ///   - indices: The index of each word in the wordlist.
    ///   - words: The words, including the final checksum word, as spelled in the wordlist.
    ///   - wordlistCount: The number of words in the wordlist.
    static func validate(indices: [Int], words: [String], wordlistCount: Int) -> Result {
        guard words.count == indices.count, let checksumWord = words.last, words.count > 1 else {
            return .invalidChecksum
        }

        // `checksum_test`: the checksum word must have the same prefix as the word selected by the CRC-32 of the
        // concatenated prefixes of the other words.
        let seedWords = words.dropLast()
        let trimmed = seedWords.map(uniquePrefix(of:)).joined()
        let checksumIndex = Int(CRC32.checksum(trimmed.utf8) % UInt32(seedWords.count))
        guard uniquePrefix(of: seedWords[checksumIndex]) == uniquePrefix(of: checksumWord) else {
            return .invalidChecksum
        }

        // `words_to_bytes`: each group of three words encodes a 32 bit value. With 1626 words, some groups would
        // need more than 32 bits, and Monero rejects the seed when the value overflows ("mumble mumble").
        let n = UInt64(wordlistCount)
        let seedIndices = indices.dropLast().map(UInt64.init)
        for group in stride(from: 0, to: seedIndices.count - 2, by: 3) {
            let w1 = seedIndices[group]
            let w2 = seedIndices[group + 1]
            let w3 = seedIndices[group + 2]
            let value = w1 + n * ((n - w1 + w2) % n) + n * n * ((n - w2 + w3) % n)
            guard value <= UInt64(UInt32.max) else { return .malformed }
        }
        return .valid
    }

    /// Mirrors `Language::utf8prefix`, which counts Unicode code points.
    private static func uniquePrefix(of word: String) -> String {
        var prefix = String.UnicodeScalarView()
        prefix.append(contentsOf: word.unicodeScalars.prefix(uniquePrefixLength))
        return String(prefix)
    }
}
