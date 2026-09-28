import Foundation
import Testing
import VaultCore

struct TOTPAuthCodeTests {
    /// The expected codes are the RFC 4226 HOTP values for the counter `epochSeconds / period`.
    @Test(arguments: [
        (30, 0, "755224"),
        (30, 59, "287082"),
        (30, 120, "338314"),
        (60, 59, "755224"),
        (60, 120, "359152"),
        (60, 179, "359152"),
        (90, 185, "359152"),
        (15, 45, "969429"),
    ] as [(UInt64, UInt64, String)])
    func renderCode_usesTheCodesPeriod(period: UInt64, epochSeconds: UInt64, expected: String) throws {
        let sut = TOTPAuthCode(period: period, data: rfcData())

        #expect(try sut.renderCode(epochSeconds: epochSeconds) == expected)
    }

    @Test
    func renderCode_zeroPeriodThrows() {
        let sut = TOTPAuthCode(period: 0, data: rfcData())

        #expect(throws: TOTPAuthCode.ZeroPeriodError.self) {
            try sut.renderCode(epochSeconds: 100)
        }
    }
}

// MARK: - Helpers

extension TOTPAuthCodeTests {
    private func rfcData() -> OTPAuthCodeData {
        OTPAuthCodeData(
            secret: .init(data: Data("12345678901234567890".utf8), format: .base32),
            accountName: "any",
        )
    }
}
