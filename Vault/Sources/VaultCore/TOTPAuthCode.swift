import CryptoEngine
import Foundation

public struct TOTPAuthCode: Sendable {
    public var period: UInt64
    public var data: OTPAuthCodeData

    public init(
        period: UInt64 = 30,
        data: OTPAuthCodeData,
    ) {
        self.period = period
        self.data = data
    }

    /// The period is zero, so there's no time step to render a code for.
    public struct ZeroPeriodError: Error {}

    public func toGenericCode() -> OTPAuthCode {
        OTPAuthCode(
            type: .totp(period: period),
            data: data,
        )
    }

    /// Renders the code for the period that `epochSeconds` falls in, using this code's own period.
    ///
    /// - Throws: `ZeroPeriodError` if the period is zero, or if an internal authentication error occurs.
    public func renderCode(epochSeconds: UInt64) throws -> String {
        guard period > 0 else { throw ZeroPeriodError() }
        let renderer = OTPCodeRenderer()
        let generator = TOTPGenerator(generator: data.hotpGenerator(), timeInterval: period)
        let code = try generator.code(epochSeconds: epochSeconds)
        return renderer.render(code: code, digits: data.digits.value)
    }
}
