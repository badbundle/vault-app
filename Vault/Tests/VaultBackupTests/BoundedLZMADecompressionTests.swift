import Foundation
import Testing
@testable import VaultBackup

struct BoundedLZMADecompressionTests {
    @Test(arguments: [0, 1, 1000, 200_000])
    func decompress_matchesFoundationsDecompression(length: Int) throws {
        let original = Data((0 ..< length).map { UInt8(truncatingIfNeeded: $0 % 251) })
        let compressed = try (original as NSData).compressed(using: .lzma) as Data

        let decompressed = try BoundedLZMADecompression.decompress(compressed)

        #expect(decompressed == original)
    }

    @Test
    func decompress_atTheLimit_decompresses() throws {
        let original = Data(repeating: 0x41, count: 4096)
        let compressed = try (original as NSData).compressed(using: .lzma) as Data

        let decompressed = try BoundedLZMADecompression.decompress(compressed, maximumLength: 4096)

        #expect(decompressed == original)
    }

    @Test
    func decompress_pastTheLimit_throws() throws {
        let compressed = try (Data(repeating: 0, count: 1 << 20) as NSData).compressed(using: .lzma) as Data

        #expect(compressed.count < 1024, "A megabyte of zeros compresses to almost nothing.")
        #expect(throws: BoundedLZMADecompression.Error.tooLarge) {
            try BoundedLZMADecompression.decompress(compressed, maximumLength: 1 << 19)
        }
    }

    @Test
    func decompress_truncatedData_throws() throws {
        let compressed = try (Data(repeating: 0x41, count: 10000) as NSData).compressed(using: .lzma) as Data

        #expect(throws: BoundedLZMADecompression.Error.invalidData) {
            try BoundedLZMADecompression.decompress(compressed.prefix(compressed.count / 2))
        }
    }

    @Test(arguments: [Data(), Data([1, 2, 3, 4]), Data(repeating: 0xFF, count: 100)])
    func decompress_dataThatIsntLZMA_throws(data: Data) {
        #expect(throws: BoundedLZMADecompression.Error.self) {
            try BoundedLZMADecompression.decompress(data)
        }
    }

    @Test
    func maximumLength_is64MiB() {
        #expect(BoundedLZMADecompression.maximumLength == 64 * 1024 * 1024)
    }
}
