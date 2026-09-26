import Foundation

/// Random bytes and wiping for the slot file.
enum SlotRandom {
    /// Bytes from the system's cryptographically secure generator. Unused slots and fill are made of these, so
    /// they have to be as unpredictable as ciphertext.
    static func bytes(count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            arc4random_buf(base, buffer.count)
        }
        return data
    }

    /// Overwrites the bytes with zeros in a way the compiler can't optimize away.
    static func wipe(_ data: inout Data) {
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = memset_s(base, buffer.count, 0, buffer.count)
        }
    }
}

extension Data {
    /// Reads a big-endian integer at `offset` from the start of the data.
    func bigEndianInteger<T: FixedWidthInteger>(at offset: Int) -> T {
        var value: T = 0
        for byte in self[(startIndex + offset) ..< (startIndex + offset + MemoryLayout<T>.size)] {
            value = value << 8 | T(byte)
        }
        return value
    }

    mutating func appendBigEndianInteger(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    /// Overwrites the bytes at `offset` from the start of the data with a big-endian integer.
    mutating func replaceBigEndianInteger(at offset: Int, with value: some FixedWidthInteger) {
        let start = startIndex + offset
        Swift.withUnsafeBytes(of: value.bigEndian) { replaceSubrange(start ..< start + $0.count, with: $0) }
    }
}
