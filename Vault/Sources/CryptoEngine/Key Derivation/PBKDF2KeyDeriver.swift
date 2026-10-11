internal import CommonCrypto
import Foundation
import FoundationExtensions

/// Derives keys with PBKDF2 (RFC 8018), using Apple's implementation in CommonCrypto.
///
/// Until VAULT-128 this was CryptoSwift's PBKDF2. CommonCrypto's derives exactly the same keys, many times faster,
/// so a slow derivation costs the user less time for the same cost to anyone guessing the password. The tests pin
/// keys CryptoSwift derived.
///
/// The salt can't be empty.
public struct PBKDF2KeyDeriver<let bytes: Int>: KeyDeriver {
    public let parameters: Parameters

    public init(parameters: Parameters) {
        self.parameters = parameters
    }

    public func key(password: Data, salt: Data) throws -> KeyData<bytes> {
        let data = try PBKDF2.derive(
            password: password,
            salt: salt,
            iterations: parameters.iterations,
            pseudoRandomFunction: parameters.variant.pseudoRandomFunction,
            length: bytes,
        )
        return try KeyData(data: data)
    }

    public var uniqueAlgorithmIdentifier: String {
        let parameters = [
            "keyLength=\(bytes)",
            "iterations=\(parameters.iterations)",
            "variant=\(parameters.variant)",
        ]
        let parametersDescription = parameters.joined(separator: ";")
        return "PBKDF2<\(parametersDescription)>"
    }
}

// MARK: - Parameters

extension PBKDF2KeyDeriver {
    public struct Parameters: Sendable {
        public enum Variant: Equatable, Sendable {
            case sha384
        }

        public var iterations: Int
        public var variant: Variant

        public init(iterations: Int, variant: Variant) {
            self.iterations = iterations
            self.variant = variant
        }
    }
}

extension PBKDF2KeyDeriver.Parameters.Variant {
    fileprivate var pseudoRandomFunction: CCPseudoRandomAlgorithm {
        switch self {
        case .sha384: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
        }
    }
}

// MARK: - PBKDF2

/// An error deriving a key with PBKDF2.
enum PBKDF2Error: Error, Equatable {
    /// The salt was empty. CommonCrypto would accept one, but CryptoSwift, which derived these keys before, didn't.
    case emptySalt
    /// The iterations weren't between 1 and `UInt32.max`.
    case iterationsOutOfRange
    /// CommonCrypto refused the derivation, with this status.
    case failed(status: Int32)
}

/// PBKDF2 itself, over CommonCrypto's `CCKeyDerivationPBKDF`.
enum PBKDF2 {
    /// Derives `length` bytes from the password, with HMAC over the given hash as the pseudorandom function.
    ///
    /// The app only uses HMAC-SHA384. The tests also use HMAC-SHA1 and HMAC-SHA256, which RFC 6070's and RFC 7914's
    /// test vectors are for.
    static func derive(
        password: Data,
        salt: Data,
        iterations: Int,
        pseudoRandomFunction: CCPseudoRandomAlgorithm,
        length: Int,
    ) throws -> Data {
        guard !salt.isEmpty else { throw PBKDF2Error.emptySalt }
        guard iterations > 0, let rounds = UInt32(exactly: iterations) else {
            throw PBKDF2Error.iterationsOutOfRange
        }
        // CommonCrypto refuses a null password, even an empty one, and an empty `Data` has no bytes to point at. A
        // byte of padding gives it an address; the length passed is still zero.
        let passwordBytes = password.isEmpty ? Data([0]) : password
        var output = Data(count: length)
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress?.assumingMemoryBound(to: CChar.self),
                        password.count,
                        saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        saltBuffer.count,
                        pseudoRandomFunction,
                        rounds,
                        outputBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        outputBuffer.count,
                    )
                }
            }
        }
        guard status == Int32(kCCSuccess) else { throw PBKDF2Error.failed(status: status) }
        return output
    }
}
