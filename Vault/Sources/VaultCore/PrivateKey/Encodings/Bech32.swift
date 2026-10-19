import Foundation

/// Bech32, as BIP-173 defines it, which Nostr's `nsec` and `npub` keys use (NIP-19).
///
/// https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
enum Bech32 {
    enum Decoded: Equatable {
        /// The human-readable part, lowercased, and the data as 8-bit bytes.
        case valid(humanReadablePart: String, data: [UInt8])
        /// Readable as bech32, but the checksum doesn't match.
        case invalidChecksum(humanReadablePart: String)
        /// Not bech32: mixed case, a character outside the charset, no separator, or data that doesn't convert to
        /// whole bytes.
        case invalid
    }

    /// "The total length of a Bech32 string is at most 90 characters" (BIP-173).
    static let maximumLength = 90

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)

    private static let generator: [UInt32] = [0x3B6A_57B2, 0x2650_8E6D, 0x1EA1_19FA, 0x3D42_33DD, 0x2A14_62B3]

    static func decode(_ text: String) -> Decoded {
        guard text.utf8.count <= maximumLength else { return .invalid }
        // "Decoders MUST NOT accept strings where some characters are uppercase and some are lowercase."
        let hasLower = text.contains { $0.isLowercase }
        let hasUpper = text.contains { $0.isUppercase }
        guard !(hasLower && hasUpper) else { return .invalid }
        let lowered = Array(text.lowercased().utf8)
        guard
            lowered.allSatisfy({ (33 ... 126).contains($0) }),
            let separator = lowered.lastIndex(of: UInt8(ascii: "1")),
            separator > 0,
            lowered.count - separator - 1 >= 6
        else { return .invalid }

        let humanReadablePart = Array(lowered[..<separator])
        var values = [UInt8]()
        for character in lowered[(separator + 1)...] {
            guard let value = charset.firstIndex(of: character) else { return .invalid }
            values.append(UInt8(value))
        }
        guard let hrp = String(bytes: humanReadablePart, encoding: .ascii) else { return .invalid }
        guard polymod(expand(humanReadablePart) + values) == 1 else {
            return .invalidChecksum(humanReadablePart: hrp)
        }
        guard let data = convertFiveBitGroups(Array(values.dropLast(6))) else { return .invalid }
        return .valid(humanReadablePart: hrp, data: data)
    }

    static func encode(humanReadablePart: String, data: [UInt8]) -> String {
        let hrp = Array(humanReadablePart.lowercased().utf8)
        let values = fiveBitGroups(of: data)
        let checksumValue = polymod(expand(hrp) + values + [0, 0, 0, 0, 0, 0]) ^ 1
        let checksum = (0 ..< 6).map { UInt8((checksumValue >> (5 * (5 - UInt32($0)))) & 31) }
        let encoded = (values + checksum).map { charset[Int($0)] }
        return String(bytes: hrp + [UInt8(ascii: "1")] + encoded, encoding: .ascii) ?? ""
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = (checksum & 0x1FFFFFF) << 5 ^ UInt32(value)
            for index in 0 ..< 5 where (top >> UInt32(index)) & 1 == 1 {
                checksum ^= generator[index]
            }
        }
        return checksum
    }

    private static func expand(_ humanReadablePart: [UInt8]) -> [UInt8] {
        humanReadablePart.map { $0 >> 5 } + [0] + humanReadablePart.map { $0 & 31 }
    }

    /// Regroups 5-bit values into bytes, refusing more than 4 bits of padding or padding that isn't zero (BIP-173's
    /// `convertbits` without padding).
    private static func convertFiveBitGroups(_ values: [UInt8]) -> [UInt8]? {
        var accumulator: UInt32 = 0
        var bits = 0
        var bytes = [UInt8]()
        for value in values {
            accumulator = (accumulator << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((accumulator >> UInt32(bits)) & 0xFF))
            }
        }
        guard bits < 5, (accumulator << UInt32(8 - bits)) & 0xFF == 0 else { return nil }
        return bytes
    }

    private static func fiveBitGroups(of bytes: [UInt8]) -> [UInt8] {
        var accumulator: UInt32 = 0
        var bits = 0
        var values = [UInt8]()
        for byte in bytes {
            accumulator = (accumulator << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                values.append(UInt8((accumulator >> UInt32(bits)) & 31))
            }
        }
        if bits > 0 {
            values.append(UInt8((accumulator << UInt32(5 - bits)) & 31))
        }
        return values
    }
}
