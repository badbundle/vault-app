import Compression
import Foundation

/// Decompresses a backup's LZMA payload, refusing one that would decompress past a limit.
///
/// A backup can come from anyone, so its payload is decompressed a chunk at a time and measured before it's kept.
/// It decompresses twice: once to measure the output, stopping if it passes `maximumLength`, and again to fill it,
/// so the output never grows by reallocating and leaving copies of the payload in freed memory. The scratch buffer
/// is wiped before it's freed.
enum BoundedLZMADecompression {
    enum Error: Swift.Error, Equatable {
        case tooLarge
        case invalidData
    }

    /// The largest payload a backup decompresses to: 64 MiB, the same limit the vault's own file has, and far more
    /// than any real vault's JSON.
    static let maximumLength = 1 << 26

    private static let chunkSize = 1 << 16

    static func decompress(_ input: Data, maximumLength: Int = maximumLength) throws -> Data {
        // Even an empty payload compresses to a header.
        guard !input.isEmpty else { throw Error.invalidData }
        var length = 0
        try process(input) { chunk in
            length += chunk.count
            guard length <= maximumLength else { throw Error.tooLarge }
        }
        var output = Data(capacity: length)
        try process(input) { output.append($0) }
        return output
    }

    /// Runs `input` through the decoder, handing each chunk of output to `receive`.
    private static func process(_ input: Data, receive: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK
        else {
            throw Error.invalidData
        }
        defer { compression_stream_destroy(stream) }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer {
            _ = memset_s(buffer, chunkSize, 0, chunkSize)
            buffer.deallocate()
        }
        let finalize = Int32(bitPattern: COMPRESSION_STREAM_FINALIZE.rawValue)

        let finished = try input.withUnsafeBytes { source -> Bool in
            // The source pointer can't be nil, even when there's nothing to read.
            stream.pointee.src_ptr = source.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(buffer)
            stream.pointee.src_size = source.count
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = chunkSize
                let remaining = stream.pointee.src_size
                let status = compression_stream_process(stream, finalize)
                let produced = chunkSize - stream.pointee.dst_size
                try receive(UnsafeBufferPointer(start: buffer, count: produced))
                switch status {
                case COMPRESSION_STATUS_END:
                    return true
                case COMPRESSION_STATUS_OK:
                    // Decoding a truncated stream stops making progress without an error.
                    if produced == 0, stream.pointee.src_size == remaining {
                        return false
                    }
                default:
                    return false
                }
            }
        }
        guard finished else { throw Error.invalidData }
    }
}
