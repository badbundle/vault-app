import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import CryptoEngine

struct Argon2idKeyDeriverTests {
    /// RFC 9106, section 5.3: Argon2id with a secret and associated data, over 4 lanes.
    @Test
    func hash_matchesRFC9106TestVector() throws {
        let tag = try Argon2id.hash(
            password: Data(repeating: 0x01, count: 32),
            salt: Data(repeating: 0x02, count: 16),
            secret: Data(repeating: 0x03, count: 8),
            associatedData: Data(repeating: 0x04, count: 12),
            parameters: Argon2idParameters(memoryKiB: 32, iterations: 3, parallelism: 4),
            length: 32,
        )

        #expect(tag == Data(hex: "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"))
    }

    /// The reference implementation's own Argon2id known-answer tests (`src/test.c`, version 0x13).
    @Test(arguments: referenceKnownAnswers)
    func key_matchesReferenceKnownAnswers(answer: KnownAnswer) throws {
        let sut = Argon2idKeyDeriver<32>(parameters: answer.parameters)

        let key = try sut.key(password: Data(answer.password.utf8), salt: Data(answer.salt.utf8))

        #expect(key.data == Data(hex: answer.hex))
    }

    @Test
    func key_isTheSameEveryTime() throws {
        let sut = Argon2idKeyDeriver<32>(parameters: .fastForTesting)
        let salt = Data(repeating: 0xAB, count: 16)

        let keys = try (0 ..< 3).map { _ in try sut.key(password: Data("password".utf8), salt: salt) }

        #expect(Set(keys).count == 1)
    }

    @Test
    func key_differsWithTheSalt() throws {
        let sut = Argon2idKeyDeriver<32>(parameters: .fastForTesting)

        let first = try sut.key(password: Data("password".utf8), salt: Data(repeating: 0x01, count: 16))
        let second = try sut.key(password: Data("password".utf8), salt: Data(repeating: 0x02, count: 16))

        #expect(first != second)
    }

    @Test
    func key_acceptsAnEmptyPassword() throws {
        let sut = Argon2idKeyDeriver<32>(parameters: .fastForTesting)

        let key = try sut.key(password: Data(), salt: Data(repeating: 0x01, count: 16))

        #expect(key.data.count == 32)
    }

    @Test
    func key_derivesTheRequestedLength() throws {
        let sut = Argon2idKeyDeriver<64>(parameters: .fastForTesting)

        let key = try sut.key(password: Data("password".utf8), salt: Data(repeating: 0x01, count: 16))

        #expect(key.data.count == 64)
    }

    @Test
    func key_throwsForASaltShorterThan8Bytes() throws {
        let sut = Argon2idKeyDeriver<32>(parameters: .fastForTesting)

        let error = try #require(throws: Argon2idError.self) {
            try sut.key(password: Data("password".utf8), salt: Data(repeating: 0x01, count: 7))
        }

        #expect(error.code == -6, "ARGON2_SALT_TOO_SHORT")
        #expect(error.errorDescription == "Salt is too short")
    }

    @Test
    func key_throwsForTooLittleMemory() throws {
        let sut = Argon2idKeyDeriver<32>(parameters: .init(memoryKiB: 1, iterations: 2, parallelism: 1))

        let error = try #require(throws: Argon2idError.self) {
            try sut.key(password: Data("password".utf8), salt: Data(repeating: 0x01, count: 16))
        }

        #expect(error.code == -14, "ARGON2_MEMORY_TOO_LITTLE")
    }

    @Test
    func key_throwsForNoPasses() throws {
        let sut = Argon2idKeyDeriver<32>(parameters: .init(memoryKiB: 64, iterations: 0, parallelism: 1))

        #expect(throws: Argon2idError.self) {
            try sut.key(password: Data("password".utf8), salt: Data(repeating: 0x01, count: 16))
        }
    }

    @Test
    func uniqueAlgorithmIdentifier_includesEveryParameter() {
        let sut = Argon2idKeyDeriver<32>(parameters: .init(memoryKiB: 65536, iterations: 7, parallelism: 1))

        #expect(
            sut.uniqueAlgorithmIdentifier ==
                "ARGON2ID<keyLength=32;memoryKiB=65536;iterations=7;parallelism=1;version=19>",
        )
    }
}

// MARK: - Wiping

extension Argon2idKeyDeriverTests {
    @Test
    func hash_wipesThePasswordBufferItIsGiven() throws {
        var password = Array("correct horse battery staple".utf8)

        _ = try password.withUnsafeMutableBytes { buffer in
            try Argon2id.hash(
                passwordBuffer: buffer,
                salt: Data(repeating: 0x01, count: 16),
                parameters: .fastForTesting,
                length: 32,
            )
        }

        #expect(password.allSatisfy { $0 == 0 })
        #expect(password.count == 28)
    }

    @Test
    func hash_wipesTheWorkingMemoryBeforeFreeingIt() throws {
        let parameters = Argon2idParameters(memoryKiB: 256, iterations: 2, parallelism: 1)
        WorkingMemoryLog.records.modify { $0.removeAll() }

        let key = try Argon2id.hash(
            password: Data("password".utf8),
            salt: Data("somesalt".utf8),
            parameters: parameters,
            length: 32,
            allocate: WorkingMemoryLog.allocate,
            free: WorkingMemoryLog.free,
        )

        let records = WorkingMemoryLog.records.get { $0 }
        let everyBlockWasWiped = records.allSatisfy(\.wasWiped)
        #expect(records.map(\.size) == [256 * 1024], "One 256 KiB block of working memory")
        #expect(everyBlockWasWiped)
        // The memory really was used: the key matches the reference's known answer for these parameters.
        #expect(key == Data(hex: "9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe"))
    }
}

// MARK: - Helpers

/// A known answer from the reference implementation's tests: `hashtest(version, t, m, p, pwd, salt, hexref, ...)`.
struct KnownAnswer: Sendable, CustomTestStringConvertible {
    var iterations: UInt32
    var memoryExponent: UInt32
    var parallelism: UInt32
    var password: String
    var salt: String
    var hex: String

    var parameters: Argon2idParameters {
        Argon2idParameters(memoryKiB: 1 << memoryExponent, iterations: iterations, parallelism: parallelism)
    }

    var testDescription: String {
        "t=\(iterations), m=2^\(memoryExponent), p=\(parallelism), \(password)/\(salt)"
    }
}

private let referenceKnownAnswers = [
    KnownAnswer(
        iterations: 2, memoryExponent: 16, parallelism: 1, password: "password", salt: "somesalt",
        hex: "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7",
    ),
    KnownAnswer(
        iterations: 2, memoryExponent: 18, parallelism: 1, password: "password", salt: "somesalt",
        hex: "78fe1ec91fb3aa5657d72e710854e4c3d9b9198c742f9616c2f085bed95b2e8c",
    ),
    KnownAnswer(
        iterations: 2, memoryExponent: 8, parallelism: 1, password: "password", salt: "somesalt",
        hex: "9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe",
    ),
    KnownAnswer(
        iterations: 2, memoryExponent: 8, parallelism: 2, password: "password", salt: "somesalt",
        hex: "6d093c501fd5999645e0ea3bf620d7b8be7fd2db59c20d9fff9539da2bf57037",
    ),
    KnownAnswer(
        iterations: 1, memoryExponent: 16, parallelism: 1, password: "password", salt: "somesalt",
        hex: "f6a5adc1ba723dddef9b5ac1d464e180fcd9dffc9d1cbf76cca2fed795d9ca98",
    ),
    KnownAnswer(
        iterations: 4, memoryExponent: 16, parallelism: 1, password: "password", salt: "somesalt",
        hex: "9025d48e68ef7395cca9079da4c4ec3affb3c8911fe4f86d1a2520856f63172c",
    ),
    KnownAnswer(
        iterations: 2, memoryExponent: 16, parallelism: 1, password: "differentpassword", salt: "somesalt",
        hex: "0b84d652cf6b0c4beaef0dfe278ba6a80df6696281d7e0d2891b817d8c458fde",
    ),
    KnownAnswer(
        iterations: 2, memoryExponent: 16, parallelism: 1, password: "password", salt: "diffsalt",
        hex: "bdf32b05ccc42eb15d58fd19b1f856b113da1e9a5874fdcc544308565aa8141c",
    ),
]

extension Argon2idParameters {
    fileprivate static var fastForTesting: Self {
        Argon2idParameters(memoryKiB: 64, iterations: 1, parallelism: 1)
    }
}

/// Allocates and frees Argon2's working memory, recording whether each block was wiped by the time it was freed.
///
/// The reference implementation's callbacks can't carry any context, so the log is global. Only
/// `hash_wipesTheWorkingMemoryBeforeFreeingIt` uses it.
private enum WorkingMemoryLog {
    struct Record: Sendable {
        var size: Int
        var wasWiped: Bool
    }

    static let records = SharedMutex<[Record]>([])

    /// Fills each block with a pattern, so a block that reaches `free` all zeros was wiped rather than never
    /// written.
    static let allocate: Argon2id.AllocateMemory = { memory, size in
        guard let memory, let block = malloc(size) else { return -22 } // ARGON2_MEMORY_ALLOCATION_ERROR
        memset(block, 0xAA, size)
        memory.pointee = block.assumingMemoryBound(to: UInt8.self)
        return 0
    }

    static let free: Argon2id.FreeMemory = { memory, size in
        guard let memory else { return }
        let wasWiped = UnsafeBufferPointer(start: memory, count: size).allSatisfy { $0 == 0 }
        WorkingMemoryLog.records.modify { $0.append(Record(size: size, wasWiped: wasWiped)) }
        Foundation.free(memory)
    }
}
