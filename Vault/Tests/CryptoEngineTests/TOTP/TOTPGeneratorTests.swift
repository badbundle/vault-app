import CryptoEngine
import CryptoSwift
import Foundation
import Testing

struct TOTPGeneratorTests {
    @Test
    func verify_matchesExpected() throws {
        let hotp = HOTPGenerator(secret: anyData())
        let sut = TOTPGenerator(generator: hotp)

        let expected = try sut.code(epochSeconds: 10)
        #expect(try sut.verify(epochSeconds: 10, value: expected))
    }

    @Test
    func verify_doesNotMatchExpected() throws {
        let hotp = HOTPGenerator(secret: anyData())
        let sut = TOTPGenerator(generator: hotp)

        let expected = try sut.code(epochSeconds: 10)
        #expect(try sut.verify(epochSeconds: 10, value: expected + 1) == false)
    }

    @Test
    func code_rollover30Seconds() throws {
        let hotp = HOTPGenerator(secret: OTPRFCSecret.sha1, digits: 8, algorithm: .sha1)
        let sut = TOTPGenerator(generator: hotp, timeInterval: 30)

        #expect(try sut.code(epochSeconds: 30) == sut.code(epochSeconds: 31))
        #expect(try sut.code(epochSeconds: 30) == sut.code(epochSeconds: 59))
        #expect(try sut.code(epochSeconds: 30) != sut.code(epochSeconds: 60))
        #expect(try sut.code(epochSeconds: 60) == sut.code(epochSeconds: 61))
        #expect(try sut.code(epochSeconds: 60) == sut.code(epochSeconds: 89))
        #expect(try sut.code(epochSeconds: 60) != sut.code(epochSeconds: 90))
    }

    @Test
    func code_zeroTimeInterval_isTreatedAsOneSecond() throws {
        let hotp = HOTPGenerator(secret: OTPRFCSecret.sha1, digits: 8, algorithm: .sha1)
        let sut = TOTPGenerator(generator: hotp, timeInterval: 0)

        #expect(sut.timeInterval == 1)
        #expect(try sut.code(epochSeconds: 59) == hotp.code(counter: 59))
    }

    @Test
    func code_rfcSHA1Example() throws {
        let hotp = HOTPGenerator(secret: OTPRFCSecret.sha1, digits: 8, algorithm: .sha1)
        let sut = TOTPGenerator(generator: hotp, timeInterval: 30)

        #expect(try sut.code(epochSeconds: 59) == 94_287_082)
        #expect(try sut.code(epochSeconds: 1_111_111_109) == 07_081_804)
        #expect(try sut.code(epochSeconds: 1_111_111_111) == 14_050_471)
        #expect(try sut.code(epochSeconds: 1_234_567_890) == 89_005_924)
        #expect(try sut.code(epochSeconds: 2_000_000_000) == 69_279_037)
        #expect(try sut.code(epochSeconds: 20_000_000_000) == 65_353_130)
    }

    @Test
    func code_rfcSHA256Example() throws {
        let hotp = HOTPGenerator(secret: OTPRFCSecret.sha256, digits: 8, algorithm: .sha256)
        let sut = TOTPGenerator(generator: hotp, timeInterval: 30)

        #expect(try sut.code(epochSeconds: 59) == 46_119_246)
        #expect(try sut.code(epochSeconds: 1_111_111_109) == 68_084_774)
        #expect(try sut.code(epochSeconds: 1_111_111_111) == 67_062_674)
        #expect(try sut.code(epochSeconds: 1_234_567_890) == 91_819_424)
        #expect(try sut.code(epochSeconds: 2_000_000_000) == 90_698_825)
        #expect(try sut.code(epochSeconds: 20_000_000_000) == 77_737_706)
    }

    @Test
    func code_rfcSHA512Example() throws {
        let hotp = HOTPGenerator(secret: OTPRFCSecret.sha512, digits: 8, algorithm: .sha512)
        let sut = TOTPGenerator(generator: hotp, timeInterval: 30)

        #expect(try sut.code(epochSeconds: 59) == 90_693_936)
        #expect(try sut.code(epochSeconds: 1_111_111_109) == 25_091_201)
        #expect(try sut.code(epochSeconds: 1_111_111_111) == 99_943_326)
        #expect(try sut.code(epochSeconds: 1_234_567_890) == 93_441_116)
        #expect(try sut.code(epochSeconds: 2_000_000_000) == 38_618_901)
        #expect(try sut.code(epochSeconds: 20_000_000_000) == 47_863_826)
    }
}
