import BigInt
import Foundation

/// # Time-based one-time password
///
/// Time-based one-time password (TOTP) is a computer algorithm that generates a one-time password (OTP) that uses the
/// current time as a source of uniqueness.
///
/// https://en.wikipedia.org/wiki/Time-based_one-time_password
public struct TOTPGenerator {
    private let generator: HOTPGenerator
    public let timeInterval: UInt64
    public var digits: UInt16 {
        generator.digits
    }

    /// A `timeInterval` of 0 is treated as 1, rather than dividing by zero.
    public init(generator: HOTPGenerator, timeInterval: UInt64 = 30) {
        self.generator = generator
        self.timeInterval = max(timeInterval, 1)
    }

    /// Generate the TOTP code using the number of seconds since the UNIX epoch.
    ///
    /// - Throws: only if an internal authentication error occurs.
    public func code(epochSeconds: UInt64) throws -> BigUInt {
        let counter = epochSeconds / timeInterval
        return try generator.code(counter: counter)
    }

    public func verify(epochSeconds: UInt64, value: BigUInt) throws -> Bool {
        let expected = try code(epochSeconds: epochSeconds)
        return expected == value
    }
}
