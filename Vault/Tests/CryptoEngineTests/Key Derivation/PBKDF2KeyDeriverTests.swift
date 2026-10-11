import CommonCrypto
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import CryptoEngine

struct PBKDF2KeyDeriverTests {
    @Test
    func key_doesNotThrowForValidParameters() {
        let sut = PBKDF2KeyDeriver<8>(parameters: .fastForTesting)

        #expect(throws: Never.self) {
            try sut.key(password: anyData(), salt: anyData())
        }
    }

    @Test
    func key_throwsIfMissingSalt() {
        let sut = PBKDF2KeyDeriver<8>(parameters: .fastForTesting)

        #expect(throws: PBKDF2Error.emptySalt) {
            try sut.key(password: anyData(), salt: emptyData())
        }
    }

    @Test(arguments: [0, -1, Int(UInt32.max) + 1])
    func key_throwsForIterationsOutOfRange(iterations: Int) {
        let sut = PBKDF2KeyDeriver<8>(parameters: .init(iterations: iterations, variant: .sha384))

        #expect(throws: PBKDF2Error.iterationsOutOfRange) {
            try sut.key(password: anyData(), salt: anyData())
        }
    }

    @Test
    func key_generatesValidKeyWithSalt() throws {
        let password = Data(byteString: "hello world")
        let salt = Data(hex: "ABCDEF")
        let sut = PBKDF2KeyDeriver<8>(parameters: .fastForTesting)

        let key = try sut.key(password: password, salt: salt)
        #expect(key.data.toHexString() == "98daafce2dc5444d")
    }

    @Test
    func key_generatesTheSameKeyMultipleTimes() throws {
        let password = Data(byteString: "hello world")
        let salt = Data(hex: "ABCDEF")
        let sut = PBKDF2KeyDeriver<8>(parameters: .fastForTesting)

        let expected = try KeyData<8>(data: Data(hex: "98daafce2dc5444d"))
        let keys = try [
            sut.key(password: password, salt: salt),
            sut.key(password: password, salt: salt),
            sut.key(password: password, salt: salt),
        ]
        #expect(keys == [expected, expected, expected])
    }

    @Test
    func uniqueAlgorithmIdentifier_matchesParameters() {
        let sut = PBKDF2KeyDeriver<8>(parameters: .init(
            iterations: 456,
            variant: .sha384,
        ))

        #expect(sut.uniqueAlgorithmIdentifier == "PBKDF2<keyLength=8;iterations=456;variant=sha384>")
    }
}

// MARK: - Known answers

extension PBKDF2KeyDeriverTests {
    /// RFC 6070's test vectors, for PBKDF2-HMAC-SHA1. The one with 16,777,216 iterations is left out, as it's slow.
    @Test(arguments: rfc6070Vectors)
    func derive_sha1_matchesRFC6070TestVectors(vector: PBKDF2Vector) throws {
        let key = try vector.derive(pseudoRandomFunction: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1))

        #expect(key == vector.key)
    }

    /// RFC 7914's test vectors for PBKDF2-HMAC-SHA256 (section 11).
    @Test(arguments: rfc7914Vectors)
    func derive_sha256_matchesRFC7914TestVectors(vector: PBKDF2Vector) throws {
        let key = try vector.derive(pseudoRandomFunction: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256))

        #expect(key == vector.key)
    }

    /// Keys CryptoSwift 1.10.0's PBKDF2-HMAC-SHA384 derived, before VAULT-128 moved the app to CommonCrypto's, for
    /// RFC 6070's inputs and for passwords, salts and lengths that take other paths. Python's `hashlib.pbkdf2_hmac`
    /// derives the same keys.
    @Test(arguments: cryptoSwiftSHA384Vectors)
    func derive_sha384_matchesTheKeysCryptoSwiftDerived(vector: PBKDF2Vector) throws {
        let key = try vector.derive(pseudoRandomFunction: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384))

        #expect(key == vector.key)
    }

    /// The PBKDF2 step of each v1 key deriver, with the parameters `VaultKeyDeriver` gives it, as CryptoSwift
    /// derived it before VAULT-128. Backups and items made before then derive their keys with these.
    @Test(arguments: [
        (2000, "4b381edd819979dc604088d7888dd4ef21520f86a044fd30e190e9af2d5777d3"), // Backup Fast v1
        (5_452_351, "03590b6bd9c64f2eda936d74b487da28650581139ca613969b2894d089d0efbb"), // Backup Secure v1
        (1001, "0705e86dbdccbb0f28468a9fb8e9602e2c9402a22738e3fc894621e55bfcebb9"), // Item Fast v1
        (372_002, "ea529c16b8c6adc4e69b1a2287318349f37ccecf50f3593b298042402097886e"), // Item Secure v1
    ])
    func key_withEachV1DeriversParameters_matchesTheKeyCryptoSwiftDerived(iterations: Int, hex: String) throws {
        let sut = PBKDF2KeyDeriver<32>(parameters: .init(iterations: iterations, variant: .sha384))

        let key = try sut.key(password: Data(byteString: "hello world"), salt: Data(byteString: "salt"))

        #expect(key.data.toHexString() == hex)
    }
}

// MARK: - Helpers

extension PBKDF2KeyDeriver.Parameters {
    static var fastForTesting: Self {
        .init(iterations: 100, variant: .sha384)
    }
}

/// A password, salt and iteration count, and the key PBKDF2 derives from them, which sets the length.
struct PBKDF2Vector: Sendable, CustomTestStringConvertible {
    var password: Data
    var salt: Data
    var iterations: Int
    var hex: String

    init(password: String, salt: String, iterations: Int, hex: String) {
        self.init(password: Data(byteString: password), salt: Data(byteString: salt), iterations: iterations, hex: hex)
    }

    init(password: Data, salt: Data, iterations: Int, hex: String) {
        self.password = password
        self.salt = salt
        self.iterations = iterations
        self.hex = hex
    }

    var key: Data {
        Data(hex: hex)
    }

    func derive(pseudoRandomFunction: CCPseudoRandomAlgorithm) throws -> Data {
        try PBKDF2.derive(
            password: password,
            salt: salt,
            iterations: iterations,
            pseudoRandomFunction: pseudoRandomFunction,
            length: hex.count / 2,
        )
    }

    var testDescription: String {
        "\(password.count) byte password, \(salt.count) byte salt, c=\(iterations), dkLen=\(hex.count / 2)"
    }
}

private let rfc6070Vectors = [
    PBKDF2Vector(password: "password", salt: "salt", iterations: 1, hex: "0c60c80f961f0e71f3a9b524af6012062fe037a6"),
    PBKDF2Vector(password: "password", salt: "salt", iterations: 2, hex: "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957"),
    PBKDF2Vector(password: "password", salt: "salt", iterations: 4096, hex: "4b007901b765489abead49d926f721d065a429c1"),
    PBKDF2Vector(
        password: "passwordPASSWORDpassword",
        salt: "saltSALTsaltSALTsaltSALTsaltSALTsalt",
        iterations: 4096,
        hex: "3d2eec4fe41c849b80c8d83662c0e44a8b291a964cf2f07038",
    ),
    PBKDF2Vector(password: "pass\0word", salt: "sa\0lt", iterations: 4096, hex: "56fa6aa75548099dcc37d7f03425e0c3"),
]

private let rfc7914Vectors = [
    PBKDF2Vector(
        password: "passwd",
        salt: "salt",
        iterations: 1,
        hex: """
        55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc\
        49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783
        """,
    ),
    PBKDF2Vector(
        password: "Password",
        salt: "NaCl",
        iterations: 80000,
        hex: """
        4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56\
        a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d
        """,
    ),
]

private let cryptoSwiftSHA384Vectors = [
    // RFC 6070's inputs, with SHA-384's 48-byte output.
    PBKDF2Vector(
        password: "password",
        salt: "salt",
        iterations: 1,
        hex: "c0e14f06e49e32d73f9f52ddf1d0c5c7191609233631dadd76a567db42b78676b38fc800cc53ddb642f5c74442e62be4",
    ),
    PBKDF2Vector(
        password: "password",
        salt: "salt",
        iterations: 2,
        hex: "54f775c6d790f21930459162fc535dbf04a939185127016a04176a0730c6f1f4fb48832ad1261baadd2cedd50814b1c8",
    ),
    PBKDF2Vector(
        password: "password",
        salt: "salt",
        iterations: 4096,
        hex: "559726be38db125bc85ed7895f6e3cf574c7a01c080c3447db1e8a76764deb3c307b94853fbe424f6488c5f4f1289626",
    ),
    PBKDF2Vector(
        password: "passwordPASSWORDpassword",
        salt: "saltSALTsaltSALTsaltSALTsaltSALTsalt",
        iterations: 4096,
        hex: """
        819143ad66df9a552559b9e131c52ae6c5c1b0eed18f4d283b8c5c9eaeb92b39\
        2c147cc2d2869d58ffe2f7da13d15f8d925721f0ed1afafa24480d55cf6060b1
        """,
    ),
    PBKDF2Vector(password: "pass\0word", salt: "sa\0lt", iterations: 4096, hex: "a3f00ac8657e095f8e0823d232fc60b3"),
    // An empty password.
    PBKDF2Vector(
        password: "",
        salt: "salt",
        iterations: 1001,
        hex: "e4944bdb48ec1c8d695c776549d02cb4f673541f409e77d30cfa8688fc11f6ee",
    ),
    // A password longer than SHA-384's 128-byte block, which HMAC hashes first.
    PBKDF2Vector(
        password: String(repeating: "a", count: 200),
        salt: "salt",
        iterations: 1001,
        hex: "3612f75900e3e6c1bc8ad41c2aa0d3bbb4729f6c6ae8a60640de325d7143a639",
    ),
    // Every byte value in the password, and 100 bytes of key: three blocks, the last one cut short.
    PBKDF2Vector(
        password: Data(0 ... 255),
        salt: Data((0 ..< 48).map { UInt8($0 * 3) }),
        iterations: 1001,
        hex: """
        adfee86bb6a34b84775d9d2e028285c18ddb7def189265af31e64c7be96df2ec\
        6bc15da74d5b3e6f8652fe70f15301fa5b8b0ba3c197dce41b11681b00df1f32\
        b8573a4606e1e041a99b2c5e69c979690a1f91f969232ceba34fa52f58d16b4d\
        838023ed
        """,
    ),
    // One byte of key, from a password that isn't ASCII.
    PBKDF2Vector(password: "café au lait", salt: "salt", iterations: 1, hex: "b8"),
]
