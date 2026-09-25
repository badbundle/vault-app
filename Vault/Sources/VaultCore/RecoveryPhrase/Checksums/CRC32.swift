import Foundation

/// CRC-32 (IEEE 802.3), as used by zlib and gzip, and by Monero (`boost::crc_32_type`).
///
/// Table-driven implementation of the sample code in RFC 1952 section 8,
/// https://www.rfc-editor.org/rfc/rfc1952#section-8: reflected polynomial `0xEDB88320` (`0x04C11DB7` reversed),
/// initial value and final XOR `0xFFFFFFFF`. Its check value (the CRC of "123456789") is `0xCBF43926`, from the
/// CRC-32/ISO-HDLC entry of https://reveng.sourceforge.io/crc-catalogue/17plus.htm.
enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { byte in
        var value = UInt32(byte)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ bytes: some Sequence<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
