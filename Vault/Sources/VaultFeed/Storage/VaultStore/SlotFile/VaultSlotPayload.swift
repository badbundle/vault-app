import Compression
import Foundation

/// What a vault's slot holds, before compression: the encoded vault, and the version of the encoding.
public struct VaultSlotPayload: Equatable, Sendable {
    /// The version of the encoding in `data`. The slot file stores it and hands it back, and the payload decoder
    /// interprets it.
    public var version: UInt32
    /// The encoded vault.
    public var data: Data

    public init(version: UInt32, data: Data) {
        self.version = version
        self.data = data
    }
}

/// How a payload is compressed in its slot. The body records it, so it can change without a new file format.
public enum VaultSlotCompression: UInt32, CaseIterable, Sendable {
    /// Stored as is.
    case none = 0
    /// LZFSE, with the Compression framework's streaming API. The app writes this: LZFSE decompresses fastest,
    /// which is what unlocking waits on.
    case lzfse = 1

    func compress(_ data: Data) throws -> Data {
        switch self {
        case .none: Data(data)
        case .lzfse: try StreamingCompression.compress(data)
        }
    }

    /// Decompresses a payload that has already been authenticated.
    ///
    /// - Throws: `VaultSlotFileError.payloadTooLarge` if it would be longer than `maximumLength`.
    func decompress(_ data: Data, maximumLength: Int) throws -> Data {
        switch self {
        case .none:
            guard data.count <= maximumLength else { throw VaultSlotFileError.payloadTooLarge }
            return Data(data)
        case .lzfse:
            return try StreamingCompression.decompress(data, maximumLength: maximumLength)
        }
    }
}

/// LZFSE through `compression_stream`, 64 KiB at a time.
///
/// The output's capacity is set before it's filled, so it never grows by reallocating, which would leave copies of
/// the payload in freed memory. The 64 KiB scratch buffer is wiped before it's freed.
enum StreamingCompression {
    static let chunkSize = 1 << 16

    /// Allocates and frees the scratch buffer. The app always uses `heap`; tests use their own, to check the buffer
    /// is wiped before it's freed.
    struct ScratchMemory: Sendable {
        var allocate: @Sendable (_ count: Int) -> UnsafeMutablePointer<UInt8>
        /// Frees a buffer `allocate` made, which has been wiped by then.
        var free: @Sendable (_ buffer: UnsafeMutablePointer<UInt8>, _ count: Int) -> Void

        static let heap = ScratchMemory(
            allocate: { UnsafeMutablePointer<UInt8>.allocate(capacity: $0) },
            free: { buffer, _ in buffer.deallocate() },
        )
    }

    /// LZFSE stores a block it can't shrink as it is, so the output is never more than a chunk longer than the
    /// input.
    static func compress(_ input: Data, scratch: ScratchMemory = .heap) throws -> Data {
        var output = Data(capacity: input.count + chunkSize)
        try process(input, operation: COMPRESSION_STREAM_ENCODE, scratch: scratch) { output.append($0) }
        return output
    }

    /// Decompresses twice: once to measure the output, stopping if it passes `maximumLength`, and again to fill
    /// it. Decompressing is the cheap direction.
    static func decompress(_ input: Data, maximumLength: Int, scratch: ScratchMemory = .heap) throws -> Data {
        var length = 0
        try process(input, operation: COMPRESSION_STREAM_DECODE, scratch: scratch) { chunk in
            length += chunk.count
            guard length <= maximumLength else { throw VaultSlotFileError.payloadTooLarge }
        }
        var output = Data(capacity: length)
        try process(input, operation: COMPRESSION_STREAM_DECODE, scratch: scratch) { output.append($0) }
        return output
    }

    /// Runs `input` through the stream, handing each chunk of output to `receive`.
    private static func process(
        _ input: Data,
        operation: compression_stream_operation,
        scratch: ScratchMemory,
        receive: (UnsafeBufferPointer<UInt8>) throws -> Void,
    ) throws {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, operation, COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK else {
            throw VaultSlotFileError.compressionFailed
        }
        defer { compression_stream_destroy(stream) }

        let buffer = scratch.allocate(chunkSize)
        defer {
            _ = memset_s(buffer, chunkSize, 0, chunkSize)
            scratch.free(buffer, chunkSize)
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
        guard finished else { throw VaultSlotFileError.compressionFailed }
    }
}
