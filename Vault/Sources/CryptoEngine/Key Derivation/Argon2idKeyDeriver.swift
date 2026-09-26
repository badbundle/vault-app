internal import CArgon2
import Foundation
import FoundationExtensions

/// The cost parameters of an Argon2id derivation (RFC 9106, section 3.1).
public struct Argon2idParameters: Equatable, Hashable, Sendable {
    /// The memory size, m, in KiB. At least 8 × `parallelism`.
    public var memoryKiB: UInt32
    /// The number of passes over the memory, t. At least 1.
    public var iterations: UInt32
    /// The number of lanes, p. At least 1.
    public var parallelism: UInt32

    public init(memoryKiB: UInt32, iterations: UInt32, parallelism: UInt32) {
        self.memoryKiB = memoryKiB
        self.iterations = iterations
        self.parallelism = parallelism
    }
}

/// Derives keys with Argon2id (RFC 9106), using the PHC reference implementation in `CArgon2`.
///
/// Argon2id is memory-hard: every derivation fills `memoryKiB` of memory, `iterations` times over, which is what
/// makes guessing passwords on GPUs and custom hardware expensive. The working memory is wiped before it's freed,
/// and so is the copy of the password the implementation is given.
///
/// The salt must be at least 8 bytes.
public struct Argon2idKeyDeriver<let bytes: Int>: KeyDeriver {
    public let parameters: Argon2idParameters

    public init(parameters: Argon2idParameters) {
        self.parameters = parameters
    }

    public func key(password: Data, salt: Data) throws -> KeyData<bytes> {
        let output = try Argon2id.hash(password: password, salt: salt, parameters: parameters, length: bytes)
        return try KeyData(data: output)
    }

    public var uniqueAlgorithmIdentifier: String {
        let parameters = [
            "keyLength=\(bytes)",
            "memoryKiB=\(parameters.memoryKiB)",
            "iterations=\(parameters.iterations)",
            "parallelism=\(parameters.parallelism)",
            "version=19",
        ]
        return "ARGON2ID<\(parameters.joined(separator: ";"))>"
    }
}

/// An error from the Argon2 reference implementation, such as parameters out of range or a salt that's too
/// short.
public struct Argon2idError: Error, Equatable, LocalizedError {
    /// The reference implementation's error code (`Argon2_ErrorCodes`).
    public let code: Int32

    public var errorDescription: String? {
        String(cString: argon2_error_message(code))
    }
}

/// Argon2id itself, over the reference implementation.
enum Argon2id {
    /// Allocates the working memory. Matches the reference's `allocate_fptr`.
    typealias AllocateMemory = @convention(c) (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, Int) -> Int32
    /// Frees the working memory, which the reference has wiped by then. Matches the reference's `deallocate_fptr`.
    typealias FreeMemory = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Void

    /// `ARGON2_FLAG_CLEAR_PASSWORD`: the reference wipes the password buffer once it's been absorbed. The macro
    /// doesn't import into Swift, so it's repeated here; the tests check the buffer is wiped.
    private static let clearPasswordFlag: UInt32 = 1 << 0
    /// `ARGON2_FLAG_CLEAR_SECRET`: the same for the secret.
    private static let clearSecretFlag: UInt32 = 1 << 1

    /// Derives `length` bytes from the password.
    ///
    /// - Parameters:
    ///   - secret: The optional key (K in RFC 9106). The app doesn't use one; the test vectors do.
    ///   - associatedData: The optional associated data (X in RFC 9106), likewise.
    ///   - allocate: Allocates the working memory. `nil` uses `malloc`.
    ///   - free: Frees the working memory after the reference has wiped it. `nil` uses `free`.
    static func hash(
        password: Data,
        salt: Data,
        secret: Data = Data(),
        associatedData: Data = Data(),
        parameters: Argon2idParameters,
        length: Int,
        allocate: AllocateMemory? = nil,
        free: FreeMemory? = nil,
    ) throws -> Data {
        var passwordCopy = [UInt8](password)
        defer { wipe(&passwordCopy) }
        return try passwordCopy.withUnsafeMutableBytes { passwordBuffer in
            try hash(
                passwordBuffer: passwordBuffer,
                salt: salt,
                secret: secret,
                associatedData: associatedData,
                parameters: parameters,
                length: length,
                allocate: allocate,
                free: free,
            )
        }
    }

    /// Derives `length` bytes from the password in `passwordBuffer`, which the reference wipes as soon as it's
    /// been absorbed.
    static func hash(
        passwordBuffer: UnsafeMutableRawBufferPointer,
        salt: Data,
        secret: Data = Data(),
        associatedData: Data = Data(),
        parameters: Argon2idParameters,
        length: Int,
        allocate: AllocateMemory? = nil,
        free: FreeMemory? = nil,
    ) throws -> Data {
        var salt = [UInt8](salt)
        var secret = [UInt8](secret)
        var associatedData = [UInt8](associatedData)
        var output = [UInt8](repeating: 0, count: length)
        defer {
            wipe(&secret)
            wipe(&output)
        }

        let result = output.withUnsafeMutableBytes { output in
            salt.withUnsafeMutableBytes { salt in
                secret.withUnsafeMutableBytes { secret in
                    associatedData.withUnsafeMutableBytes { associatedData in
                        var context = argon2_context(
                            out: output.bindMemory(to: UInt8.self).baseAddress,
                            outlen: UInt32(output.count),
                            pwd: passwordBuffer.bindMemory(to: UInt8.self).baseAddress,
                            pwdlen: UInt32(passwordBuffer.count),
                            salt: salt.bindMemory(to: UInt8.self).baseAddress,
                            saltlen: UInt32(salt.count),
                            secret: secret.bindMemory(to: UInt8.self).baseAddress,
                            secretlen: UInt32(secret.count),
                            ad: associatedData.bindMemory(to: UInt8.self).baseAddress,
                            adlen: UInt32(associatedData.count),
                            t_cost: parameters.iterations,
                            m_cost: parameters.memoryKiB,
                            lanes: parameters.parallelism,
                            threads: parameters.parallelism,
                            version: UInt32(ARGON2_VERSION_13.rawValue),
                            allocate_cbk: allocate,
                            free_cbk: free,
                            flags: clearPasswordFlag | clearSecretFlag,
                        )
                        return argon2_ctx(&context, Argon2_id)
                    }
                }
            }
        }
        guard result == ARGON2_OK.rawValue else {
            throw Argon2idError(code: result)
        }
        return Data(output)
    }

    /// Overwrites the bytes with zeros in a way the compiler can't optimize away.
    private static func wipe(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = memset_s(base, buffer.count, 0, buffer.count)
        }
    }
}
