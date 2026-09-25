import Foundation

/// Validation of a single SLIP-39 share mnemonic.
///
/// Specification: https://github.com/satoshilabs/slips/blob/master/slip-0039.md ("Format of the share mnemonic",
/// "Checksum" and "Combining the shares"). Reference implementation: `Share.from_mnemonic` in
/// https://github.com/trezor/python-shamir-mnemonic/blob/master/shamir_mnemonic/share.py.
///
/// Each word encodes 10 bits (big-endian). A share is laid out as:
/// identifier (15 bits), extendable flag (1), iteration exponent (4), group index (4), group threshold (4),
/// group count (4), member index (4), member threshold (4), the padded share value, then a 30 bit RS1024 checksum.
///
/// Only the checks that can be made on a single share are performed. Whether shares belong together (same
/// identifier, thresholds and so on) can only be known when combining them.
enum SLIP39Share {
    enum Result: Equatable {
        case valid(extendable: Bool)
        case invalidChecksum
        /// The checksum is valid but the share is malformed, such as having non-zero padding.
        case malformed
    }

    private static let bitsPerWord = 10
    private static let identifierAndExponentWords = 2
    private static let parameterWords = 2
    private static let checksumWords = 3
    private static let metadataWords = identifierAndExponentWords + parameterWords + checksumWords
    private static let minimumWords = 20

    private static let generator = [
        0xE0E040, 0x1C1C080, 0x3838100, 0x7070200, 0xE0E0009,
        0x1C0C_2412, 0x3808_6C24, 0x3090_FC48, 0x21B1_F890, 0x3F3F120,
    ]

    /// - Parameter indices: The index of each word in the SLIP-39 wordlist.
    static func validate(indices: [Int]) -> Result {
        // "The length of each share value MUST be at least 128 bits": 13 words of share value, plus 7 of metadata.
        guard indices.count >= minimumWords else { return .malformed }
        // "The length of the padding of the share value in bits, which is equal to the length of the padded share
        // value in bits modulo 16, MUST NOT exceed 8 bits."
        let paddingBits = (bitsPerWord * (indices.count - metadataWords)) % 16
        guard paddingBits <= 8 else { return .malformed }

        // The first two words are the identifier (15 bits), extendable flag (1) and iteration exponent (4). "The
        // customization string (cs) of RS1024 is "shamir" if ext = 0 and "shamir_extendable" if ext = 1."
        let identifierAndExponent = (indices[0] << bitsPerWord) | indices[1]
        let isExtendable = (identifierAndExponent >> 4) & 1 == 1
        let customization = isExtendable ? "shamir_extendable" : "shamir"
        guard rs1024Polymod(customization.utf8.map(Int.init) + indices) == 1 else { return .invalidChecksum }

        // The next two words are the group index, group threshold - 1, group count - 1, member index and member
        // threshold - 1, 4 bits each. "The value of G MUST be greater than or equal to GT."
        let parameters = (indices[2] << bitsPerWord) | indices[3]
        let groupThreshold = ((parameters >> 12) & 0xF) + 1
        let groupCount = ((parameters >> 8) & 0xF) + 1
        guard groupThreshold <= groupCount else { return .malformed }

        // The share value "is left-padded with "0" bits so that the length of the padded share value in bits becomes
        // the nearest multiple of 10", and "All padding bits MUST be "0".".
        let firstValueWord = indices[identifierAndExponentWords + parameterWords]
        guard firstValueWord >> (bitsPerWord - paddingBits) == 0 else { return .malformed }

        return .valid(extendable: isExtendable)
    }

    /// `rs1024_polymod` from the "Checksum" section of the specification. A share is valid when this is 1 for the
    /// US-ASCII values of the customization string followed by the word indices.
    private static func rs1024Polymod(_ values: [Int]) -> Int {
        var checksum = 1
        for value in values {
            let top = checksum >> 20
            checksum = ((checksum & 0xFFFFF) << 10) ^ value
            for bit in 0 ..< 10 where (top >> bit) & 1 == 1 {
                checksum ^= generator[bit]
            }
        }
        return checksum
    }
}
