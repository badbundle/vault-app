import CryptoKit
import Foundation
import FoundationExtensions

/// The checksum embedded in a BIP39 mnemonic.
///
/// From "Generating the mnemonic" in https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki: the entropy
/// (ENT, 128 to 256 bits, a multiple of 32) is followed by a checksum of its first `ENT / 32` bits of SHA-256, and
/// the result is split into 11 bit groups (big-endian), each the index of a word. So 12, 15, 18, 21 or 24 words
/// carry a 4 to 8 bit checksum.
///
/// The checksum catches most mistyped or reordered words, but not all: with 4 bits, 1 in 16 random changes to a
/// 12 word phrase still passes.
enum BIP39Checksum {
    static let bitsPerWord = 11

    /// - Parameter indices: The index of each word in its wordlist. The count must be a multiple of 3.
    static func isValid(indices: [Int]) -> Bool {
        let totalBits = indices.count * bitsPerWord
        // ENT + ENT / 32 = 33 * ENT / 32, so the total is a multiple of 33 and the checksum is 1/33 of it.
        guard indices.isNotEmpty, totalBits % 33 == 0 else { return false }
        let checksumBits = totalBits / 33
        let entropyBits = totalBits - checksumBits

        var bits = [Bool]()
        bits.reserveCapacity(totalBits)
        for index in indices {
            for shift in (0 ..< bitsPerWord).reversed() {
                bits.append((index >> shift) & 1 == 1)
            }
        }

        var entropy = [UInt8](repeating: 0, count: entropyBits / 8)
        for bitIndex in 0 ..< entropyBits where bits[bitIndex] {
            entropy[bitIndex / 8] |= 0x80 >> (bitIndex % 8)
        }

        let hash = Array(SHA256.hash(data: entropy))
        for bitIndex in 0 ..< checksumBits {
            let expected = (hash[bitIndex / 8] >> (7 - bitIndex % 8)) & 1 == 1
            if bits[entropyBits + bitIndex] != expected {
                return false
            }
        }
        return true
    }
}
