import Foundation
import Testing
import VaultCore

struct OTPAuthURIDecoderTests {
    let sut = OTPAuthURIDecoder()

    @Test(arguments: [
        "http://",
        "http://example.com",
        "https://",
        "https://example.com",
        "notvalid://",
        "notvalid://example",
        "://",
    ])
    func decodeScheme_invalidSchemeThrowsError(uri: String) throws {
        #expect(throws: OTPAuthURIDecoder.URIDecodingError.invalidScheme) {
            try sut.decode(uri)
        }
    }

    @Test
    func decodeType_decodesTotpType() throws {
        let value = "otpauth://totp/any"
        let code = try sut.decode(value)

        #expect(code.type.kind == .totp)
    }

    @Test
    func decodeType_decodesHotpType() throws {
        let value = "otpauth://hotp/any"
        let code = try sut.decode(value)

        #expect(code.type.kind == .hotp)
    }

    @Test
    func decodeType_throwsErrorForInvalidType() throws {
        let value = "otpauth://invalid/any"

        #expect(throws: OTPAuthURIDecoder.URIDecodingError.invalidType) {
            try sut.decode(value)
        }
    }

    @Test
    func decodeType_usesDefaultTotpTimingIfNotSpecified() throws {
        let value = "otpauth://totp/any"
        let code = try sut.decode(value)

        #expect(code.type == .totp(period: 30))
    }

    @Test
    func decodeType_usesDefaultHotpCounterIfNotSpecified() throws {
        let value = "otpauth://hotp/any"
        let code = try sut.decode(value)

        #expect(code.type == .hotp(counter: 0))
    }

    @Test
    func decodeType_decodesTotpPeriod() throws {
        let value = "otpauth://totp/any?period=69"
        let code = try sut.decode(value)

        #expect(code.type == .totp(period: 69))
    }

    @Test
    func decodeType_throwsErrorForZeroPeriod() throws {
        let value = "otpauth://totp/any?period=0"

        #expect(throws: OTPAuthURIDecoder.URIDecodingError.invalidValue) {
            try sut.decode(value)
        }
    }

    @Test
    func decodeType_decodesTheLargestPeriodTheVaultStores() throws {
        let value = "otpauth://totp/any?period=\(Int64.max)"
        let code = try sut.decode(value)

        #expect(code.type == .totp(period: UInt64(Int64.max)))
    }

    @Test(arguments: ["period=9223372036854775808", "period=18446744073709551615"])
    func decodeType_throwsErrorForPeriodTooLargeToStore(parameter: String) throws {
        let value = "otpauth://totp/any?\(parameter)"

        #expect(throws: OTPAuthURIDecoder.URIDecodingError.invalidValue) {
            try sut.decode(value)
        }
    }

    @Test(arguments: ["counter=9223372036854775808", "counter=18446744073709551615"])
    func decodeType_throwsErrorForCounterTooLargeToStore(parameter: String) throws {
        let value = "otpauth://hotp/any?\(parameter)"

        #expect(throws: OTPAuthURIDecoder.URIDecodingError.invalidValue) {
            try sut.decode(value)
        }
    }

    @Test
    func decodeType_decodesHotpCounter() throws {
        let value = "otpauth://hotp/any?counter=420"
        let code = try sut.decode(value)

        #expect(code.type == .hotp(counter: 420))
    }

    @Test(arguments: [
        "otpauth://totp/Hello%20World",
        "otpauth://hotp/Hello%20World",
        "otpauth://totp/Issuer:Hello%20World",
        "otpauth://totp/Issuer:Extra:Colons:Invalid:Hello%20World",
        "otpauth://totp/Issuer:%20%20Hello%20World%20%20",
    ])
    func decodeLabel_decodesAccountName(uri: String) throws {
        let code = try sut.decode(uri)

        #expect(code.data.accountName == "Hello World")
    }

    @Test
    func decodeIssuer_decodesNoIssuerIfNotPresent() throws {
        let value = "otpauth://totp/any"
        let code = try sut.decode(value)

        #expect(code.data.issuer == "")
    }

    @Test(arguments: [
        "otpauth://totp/%20Some%20Issuer%20:any",
        "otpauth://totp/any?issuer=%20Some%20Issuer%20",
        "otpauth://totp/Disfavored:any?issuer=20Some%20Issuer", // prefers parameter
    ])
    func decodeIssuer_decodesIssuer(uri _: String) throws {
        let value = "otpauth://totp/%20Some%20Issuer%20:any"
        let code = try sut.decode(value)

        #expect(code.data.issuer == "Some Issuer")
    }

    @Test
    func decodeAlgorithm_defaultsToSHA1() throws {
        let value = "otpauth://totp/any"
        let code = try sut.decode(value)

        #expect(code.data.algorithm == .sha1)
    }

    @Test(arguments: [
        ("otpauth://totp/any?algorithm=SHA1", .sha1),
        ("otpauth://totp/any?algorithm=SHA256", .sha256),
        ("otpauth://totp/any?algorithm=SHA512", .sha512),
    ] as [(String, OTPAuthAlgorithm)])
    func decodeAlgorithm_usesValue(uri: String, algorithm: OTPAuthAlgorithm) throws {
        let code = try sut.decode(uri)

        #expect(code.data.algorithm == algorithm)
    }

    @Test(arguments: [
        "otpauth://totp/any?algorithm=BAD",
        "otpauth://totp/any?algorithm=%20",
    ])
    func decodeAlgorithm_throwsForInvalidAlgorithm(uri: String) {
        #expect(throws: OTPAuthURIDecoder.URIDecodingError.invalidAlgorithm, performing: {
            try sut.decode(uri)
        })
    }

    @Test
    func decodeDigits_defaultstoSix() throws {
        let value = "otpauth://totp/any"
        let code = try sut.decode(value)

        #expect(code.data.digits.value == 6)
    }

    @Test(arguments: [
        ("otpauth://totp/any?digits=6", 6),
        ("otpauth://totp/any?digits=8", 8),
        ("otpauth://totp/any?digits=12", 12),

    ] as [(String, OTPAuthDigits)])
    func decodeDigits_validDigits(uri: String, digits: OTPAuthDigits) throws {
        let code = try sut.decode(uri)

        #expect(code.data.digits == digits)
    }

    @Test(arguments: [
        "otpauth://totp/any?digits=-1",
        "otpauth://totp/any?digits=-10",
        "otpauth://totp/any?digits=-9999",
    ])
    func decodeDigits_throwsForNegativeNumber(uri: String) {
        #expect(throws: OTPAuthURIDecoder.URIDecodingError.invalidValue, performing: {
            try sut.decode(uri)
        })
    }

    @Test(arguments: [
        "otpauth://totp/any?digits=80000",
        "otpauth://totp/any?digits=99999999999999",
    ])
    func decodeDigits_throwsForTooLargeNumber(uri: String) {
        #expect(throws: OTPAuthURIDecoder.URIDecodingError.invalidValue, performing: {
            try sut.decode(uri)
        })
    }

    @Test
    func decodeSecret_defaultsToEmptySecretBase32() throws {
        let value = "otpauth://totp/any"
        let code = try sut.decode(value)

        #expect(code.data.secret.data == Data())
        #expect(code.data.secret.format == .base32)
    }

    @Test
    func decodeSecret_decodesBase32Secret() throws {
        let value = "otpauth://totp/any?secret=5372UEJC"
        let code = try sut.decode(value)
        let expectedBytes: [UInt8] = [0xEE, 0xFF, 0xAA, 0x11, 0x22]

        #expect(code.data.secret.data == Data(expectedBytes))
        #expect(code.data.secret.format == .base32)
    }

    @Test
    func decodeSecret_decodesBase32SecretWithPadding() throws {
        let value = "otpauth://totp/any?secret=5372UEJC77XA%3D%3D%3D%3D"
        let code = try sut.decode(value)
        let expectedBytes: [UInt8] = [0xEE, 0xFF, 0xAA, 0x11, 0x22, 0xFF, 0xEE]

        #expect(code.data.secret.data == Data(expectedBytes))
        #expect(code.data.secret.format == .base32)
    }

    @Test(arguments: [
        "otpauth://totp/any?secret=ee~~~",
        "otpauth://totp/any?secret=1x%20",
    ])
    func decodeSecret_invalidBase32ThrowsDecodingError(uri: String) {
        #expect(throws: (any Error).self, performing: {
            try sut.decode(uri)
        })
    }

    @Test
    func decode_decodesAllParameters() throws {
        let value = "otpauth://totp/Issuer:Account?period=69&digits=8&algorithm=SHA512&issuer=Issuer&secret=5372UEJC"
        let code = try sut.decode(value)
        let expectedBytes: [UInt8] = [0xEE, 0xFF, 0xAA, 0x11, 0x22]

        #expect(code.type == .totp(period: 69))
        #expect(code.data.secret.data == Data(expectedBytes))
        #expect(code.data.secret.format == .base32)
        #expect(code.data.algorithm == .sha512)
        #expect(code.data.digits == 8)
        #expect(code.data.issuer == "Issuer")
        #expect(code.data.accountName == "Account")
    }
}

extension OTPAuthURIDecoder {
    fileprivate func decode(_ testCaseValue: String) throws -> OTPAuthCode {
        let uri = try #require(OTPAuthURI(string: testCaseValue), "Not a valid url.")
        return try decode(uri: uri)
    }
}
