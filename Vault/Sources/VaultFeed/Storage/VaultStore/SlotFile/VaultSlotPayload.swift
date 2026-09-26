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
        case .lzfse: try StreamingCompression.process(data, operation: COMPRESSION_STREAM_ENCODE)
        }
    }

    /// Decompresses a payload that has already been authenticated.
    func decompress(_ data: Data) throws -> Data {
        switch self {
        case .none: Data(data)
        case .lzfse: try StreamingCompression.process(data, operation: COMPRESSION_STREAM_DECODE)
        }
    }
}

/// LZFSE through `compression_stream`, 64 KiB of output at a time.
private enum StreamingCompression {
    static func process(_ input: Data, operation: compression_stream_operation) throws -> Data {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, operation, COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK else {
            throw VaultSlotFileError.compressionFailed
        }
        defer { compression_stream_destroy(stream) }

        let bufferSize = 1 << 16
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        let finalize = Int32(bitPattern: COMPRESSION_STREAM_FINALIZE.rawValue)

        var output = Data()
        let finished = input.withUnsafeBytes { source -> Bool in
            // The source pointer can't be nil, even when there's nothing to read.
            stream.pointee.src_ptr = source.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(buffer)
            stream.pointee.src_size = source.count
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                let remaining = stream.pointee.src_size
                let status = compression_stream_process(stream, finalize)
                let produced = bufferSize - stream.pointee.dst_size
                output.append(buffer, count: produced)
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
        return output
    }
}
