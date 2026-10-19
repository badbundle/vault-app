import CryptoKit
import Foundation

/// Bitcoin's Base58 alphabet and Base58Check: the payload, then the first four bytes of its double SHA-256.
///
/// https://en.bitcoin.it/wiki/Base58Check_encoding. Hashing isn't encryption, so CryptoKit's SHA-256 is used as
/// docs/export-compliance.md allows.
enum Base58Check {
    enum Decoded: Equatable {
        case valid(payload: [UInt8])
        /// Only Base58 characters, but the last four bytes aren't the checksum of the rest.
        case invalidChecksum
        /// Something that isn't in the Base58 alphabet, or too short to have a checksum.
        case notBase58
    }

    /// Longer text isn't a key Vault reads as Base58, and decoding is quadratic in its length.
    static let maximumLength = 120

    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    private static let digitValues: [Int8] = {
        var values = [Int8](repeating: -1, count: 128)
        for (value, character) in alphabet.enumerated() {
            values[Int(character)] = Int8(value)
        }
        return values
    }()

    static func isBase58(_ text: String) -> Bool {
        text.utf8.allSatisfy { $0 < 128 && digitValues[Int($0)] >= 0 }
    }

    static func decode(_ text: String) -> Decoded {
        guard text.utf8.count <= maximumLength, let bytes = decodeBase58(text), bytes.count > 4 else {
            return .notBase58
        }
        let payload = Array(bytes.dropLast(4))
        let checksum = Array(bytes.suffix(4))
        return checksum == Self.checksum(of: payload) ? .valid(payload: payload) : .invalidChecksum
    }

    static func encode(_ payload: [UInt8]) -> String {
        encodeBase58(payload + checksum(of: payload))
    }

    private static func checksum(of payload: [UInt8]) -> [UInt8] {
        let first = SHA256.hash(data: payload)
        return Array(SHA256.hash(data: Array(first)).prefix(4))
    }

    private static func decodeBase58(_ text: String) -> [UInt8]? {
        // Little-endian while it's built up, so each digit only multiplies what's there and carries upwards.
        var littleEndian = [UInt8]()
        for character in text.utf8 {
            guard character < 128 else { return nil }
            let value = digitValues[Int(character)]
            guard value >= 0 else { return nil }
            var carry = Int(value)
            for index in littleEndian.indices {
                carry += Int(littleEndian[index]) * 58
                littleEndian[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                littleEndian.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        // Each leading "1" is a leading zero byte.
        let leadingZeros = text.utf8.prefix { $0 == alphabet[0] }.count
        return [UInt8](repeating: 0, count: leadingZeros) + littleEndian.reversed()
    }

    private static func encodeBase58(_ bytes: [UInt8]) -> String {
        var littleEndianDigits = [UInt8]()
        for byte in bytes {
            var carry = Int(byte)
            for index in littleEndianDigits.indices {
                carry += Int(littleEndianDigits[index]) << 8
                littleEndianDigits[index] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                littleEndianDigits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        let leadingZeros = bytes.prefix { $0 == 0 }.count
        let digits = [UInt8](repeating: 0, count: leadingZeros) + littleEndianDigits.reversed()
        // Only ever the alphabet's ASCII.
        return String(bytes: digits.map { alphabet[Int($0)] }, encoding: .ascii) ?? ""
    }
}
