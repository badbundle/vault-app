import CryptoKit
import Foundation
import FoundationExtensions

/// The checksum embedded in a BIP39 mnemonic.
///
/// Each word encodes 11 bits. The concatenated bits are the entropy followed by a checksum, which is the first
/// `entropy bits / 32` bits of the SHA-256 of the entropy.
enum BIP39Checksum {
    static let bitsPerWord = 11

    /// - Parameter indices: The index of each word in its wordlist. The count must be a multiple of 3.
    static func isValid(indices: [Int]) -> Bool {
        let totalBits = indices.count * bitsPerWord
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
