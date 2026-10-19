import Foundation

/// The range of secp256k1 private keys: any 32-byte number from 1 to `n - 1`, where `n` is the order of the curve.
///
/// "Standards for Efficient Cryptography 2", https://www.secg.org/sec2-v2.pdf, section 2.4.1. BIP32 calls a key
/// outside it invalid ("the key is invalid", "Private key derivation"), and so do WIF and Nostr keys, which are the
/// same
/// numbers. Only the range is checked: nothing is derived from the key.
enum Secp256k1 {
    /// `n`, big-endian.
    static let order: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
        0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B, 0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41,
    ]

    /// Whether `key`, 32 bytes big-endian, is from 1 to `n - 1`.
    static func isValidPrivateKey(_ key: some Collection<UInt8>) -> Bool {
        guard key.count == 32, key.contains(where: { $0 != 0 }) else { return false }
        return key.lexicographicallyPrecedes(order)
    }
}

/// The CRC-24 that ends an ASCII armored OpenPGP block.
///
/// RFC 4880, section 6.1 (https://www.rfc-editor.org/rfc/rfc4880#section-6.1), kept as optional in RFC 9580.
enum CRC24 {
    static func checksum(_ bytes: some Sequence<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xB704CE
        for byte in bytes {
            crc ^= UInt32(byte) << 16
            for _ in 0 ..< 8 {
                crc <<= 1
                if crc & 0x1000000 != 0 {
                    crc ^= 0x1864CFB
                }
            }
        }
        return crc & 0xFFFFFF
    }
}

/// Reads the big-endian lengths and length-prefixed strings that OpenSSH's key format is made of.
///
/// RFC 4251, section 5 (https://www.rfc-editor.org/rfc/rfc4251#section-5).
struct SSHWireReader {
    private var bytes: ArraySlice<UInt8>

    init(_ bytes: some Collection<UInt8>) {
        self.bytes = ArraySlice(bytes)
    }

    var isAtEnd: Bool {
        bytes.isEmpty
    }

    mutating func readBytes(count: Int) -> ArraySlice<UInt8>? {
        guard count >= 0, bytes.count >= count else { return nil }
        let read = bytes.prefix(count)
        bytes = bytes.dropFirst(count)
        return read
    }

    mutating func readUInt32() -> UInt32? {
        guard let read = readBytes(count: 4) else { return nil }
        return read.reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func readString() -> ArraySlice<UInt8>? {
        guard let length = readUInt32(), length <= UInt32(Int32.max) else { return nil }
        return readBytes(count: Int(length))
    }
}

/// Reads one DER value at a time: its tag and contents. Only what PEM keys need: no indefinite lengths.
///
/// ITU-T X.690, section 8.1 (https://www.itu.int/rec/T-REC-X.690).
struct DERReader {
    static let sequence: UInt8 = 0x30
    static let integer: UInt8 = 0x02
    static let octetString: UInt8 = 0x04
    static let objectIdentifier: UInt8 = 0x06

    private var bytes: ArraySlice<UInt8>

    init(_ bytes: some Collection<UInt8>) {
        self.bytes = ArraySlice(bytes)
    }

    var isAtEnd: Bool {
        bytes.isEmpty
    }

    mutating func read() -> (tag: UInt8, contents: ArraySlice<UInt8>)? {
        guard let tag = bytes.first, let lengthByte = bytes.dropFirst().first else { return nil }
        var remaining = bytes.dropFirst(2)
        let length: Int
        if lengthByte < 0x80 {
            length = Int(lengthByte)
        } else {
            let lengthOfLength = Int(lengthByte & 0x7F)
            guard (1 ... 4).contains(lengthOfLength), remaining.count >= lengthOfLength else { return nil }
            length = remaining.prefix(lengthOfLength).reduce(0) { $0 << 8 | Int($1) }
            remaining = remaining.dropFirst(lengthOfLength)
        }
        guard remaining.count >= length else { return nil }
        bytes = remaining.dropFirst(length)
        return (tag, remaining.prefix(length))
    }

    /// The next value, if it has `tag`.
    mutating func read(tag expected: UInt8) -> ArraySlice<UInt8>? {
        var lookahead = self
        guard let (tag, contents) = lookahead.read(), tag == expected else { return nil }
        self = lookahead
        return contents
    }
}
