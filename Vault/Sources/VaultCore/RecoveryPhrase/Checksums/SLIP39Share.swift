import Foundation

/// Validation of a single SLIP-39 share mnemonic.
///
/// Each word encodes 10 bits. A share is laid out as:
/// identifier (15 bits), extendable flag (1), iteration exponent (4), group index (4), group threshold (4),
/// group count (4), member index (4), member threshold (4), the padded share value, then a 30 bit RS1024 checksum.
///
/// Mirrors `Share.from_mnemonic` in `trezor/python-shamir-mnemonic`. Only checks that can be made on a single share
/// are performed: whether shares belong together can only be known when combining them.
enum SLIP39Share {
    enum Result: Equatable {
        case valid(extendable: Bool)
        case invalidChecksum
        /// The checksum is valid but the share is malformed, such as having non-zero padding.
        case invalidShare
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
        guard indices.count >= minimumWords else { return .invalidShare }
        let paddingBits = (bitsPerWord * (indices.count - metadataWords)) % 16
        guard paddingBits <= 8 else { return .invalidShare }

        let identifierAndExponent = (indices[0] << bitsPerWord) | indices[1]
        let isExtendable = (identifierAndExponent >> 4) & 1 == 1
        let customization = isExtendable ? "shamir_extendable" : "shamir"
        guard rs1024Polymod(customization.utf8.map(Int.init) + indices) == 1 else { return .invalidChecksum }

        let parameters = (indices[2] << bitsPerWord) | indices[3]
        let groupThreshold = ((parameters >> 12) & 0xF) + 1
        let groupCount = ((parameters >> 8) & 0xF) + 1
        guard groupThreshold <= groupCount else { return .invalidShare }

        // The share value is left-padded to a whole number of words, and the padding must be zero.
        let firstValueWord = indices[identifierAndExponentWords + parameterWords]
        guard firstValueWord >> (bitsPerWord - paddingBits) == 0 else { return .invalidShare }

        return .valid(extendable: isExtendable)
    }

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
