import Foundation
import FoundationExtensions

/// Common internal data used by OTP codes.
public struct OTPAuthCodeData: Equatable, Hashable, Sendable {
    public var secret: OTPAuthSecret
    public var algorithm: OTPAuthAlgorithm
    public var digits: OTPAuthDigits
    public var accountName: String
    public var issuer: String

    public init(
        secret: OTPAuthSecret,
        algorithm: OTPAuthAlgorithm = .default,
        digits: OTPAuthDigits = .default,
        accountName: String,
        issuer: String = "",
    ) {
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.accountName = accountName
        self.issuer = issuer
    }
}

public struct OTPAuthSecret: Equatable, Hashable, Sendable {
    public var data: Data
    /// The format that the secret was stored in.
    public var format: Format

    public enum Format: Equatable, Hashable, Sendable {
        case base32
    }

    public init(data: Data, format: Format) {
        self.data = data
        self.format = format
    }

    public static func empty(_ format: Format = .base32) -> OTPAuthSecret {
        .init(data: Data(), format: format)
    }

    public static func base32EncodedString(_ string: String) throws(Base32Error) -> OTPAuthSecret {
        let data = try string.base32DecodedData
        return .init(data: data, format: .base32)
    }

    public var base32EncodedString: String {
        base32Encode(data)
    }
}

public struct OTPAuthDigits: Equatable, Hashable, CustomStringConvertible, Sendable {
    public var value: UInt16

    public init(value: UInt16) {
        self.value = value
    }

    public var description: String {
        "\(value)"
    }
}

extension OTPAuthDigits: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = UInt16

    public init(integerLiteral value: UInt16) {
        self.value = value
    }
}

extension OTPAuthDigits {
    public static var `default`: OTPAuthDigits {
        .init(value: 6)
    }
}

public enum OTPAuthAlgorithm: Equatable, Hashable, IdentifiableSelf, CaseIterable, Sendable {
    case sha1
    case sha256
    case sha512

    public static var `default`: OTPAuthAlgorithm {
        .sha1
    }

    public var stringValue: String {
        switch self {
        case .sha1: "SHA1"
        case .sha256: "SHA256"
        case .sha512: "SHA512"
        }
    }
}

public enum OTPAuthType: Equatable, Hashable, Sendable {
    case totp(period: UInt64 = TOTP.defaultPeriod)
    case hotp(counter: UInt64 = HOTP.defaultCounter)

    public enum TOTP {
        public static var defaultPeriod: UInt64 {
            30
        }

        /// The periods a code can have, in seconds: at least one, and small enough for the `Int64` the vault stores.
        public static let validPeriods: ClosedRange<UInt64> = 1 ... UInt64(Int64.max)
    }

    public enum HOTP {
        public static var defaultCounter: UInt64 {
            0
        }

        /// The counters a code can have: small enough for the `Int64` the vault stores.
        public static let validCounters: ClosedRange<UInt64> = 0 ... UInt64(Int64.max)
    }

    /// Whether the vault can store this period or counter, and make codes with it.
    public var isValid: Bool {
        switch self {
        case let .totp(period): TOTP.validPeriods.contains(period)
        case let .hotp(counter): HOTP.validCounters.contains(counter)
        }
    }

    public enum Kind: Equatable, Hashable, IdentifiableSelf, CaseIterable, Sendable {
        case totp, hotp
    }

    public var kind: Kind {
        switch self {
        case .totp:
            .totp
        case .hotp:
            .hotp
        }
    }
}
