import Foundation

/// A key that is generic over a specific byte length.
public struct KeyData<let bytes: Int>: Equatable, Hashable, Sendable {
    public let data: Data

    public struct LengthError: Error {}

    public init(data: Data) throws(LengthError) {
        guard data.count == bytes else { throw LengthError() }
        self.data = data
    }
}

// MARK: - Redaction

// A key's bytes must never end up in a log, crash report or test failure message via string interpolation or
// reflection (`Data`'s own mirror lists its bytes), so all textual representations leave them out.

extension KeyData: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "KeyData<\(bytes)>(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [], displayStyle: .struct)
    }
}

extension KeyData: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        try self.init(data: data)
    }
}

extension KeyData {
    public static var length: Int {
        bytes
    }

    public static func zero() -> Self {
        .repeating(byte: 0x00)
    }

    public static func random() -> Self {
        // Force try: This is of the same length as the key, so it will not throw.
        // swiftlint:disable:next force_try
        try! .init(data: .random(count: length))
    }

    public static func repeating(byte: UInt8) -> Self {
        // Force try: This is of the same length as the key, so it will not throw.
        // swiftlint:disable:next force_try
        try! .init(data: Data(repeating: byte, count: length))
    }
}
