import Foundation

/// Decodes according to the spec for *otpauth*.
///
/// https://docs.yubico.com/yesdk/users-manual/application-oath/uri-string-format.html
public struct OTPAuthURIDecoder {
    public enum URIDecodingError: Error {
        case invalidScheme
        case invalidType
        case invalidLabel
        case invalidAlgorithm
        case invalidValue
    }

    public init() {}

    public func decode(uri: OTPAuthURI) throws -> OTPAuthCode {
        guard let scheme = uri.scheme, scheme == OTPAuthURI.otpAuthScheme else {
            throw URIDecodingError.invalidScheme
        }
        let label = try decodeLabel(uri: uri)
        return try OTPAuthCode(
            type: decodeType(uri: uri),
            data: OTPAuthCodeData(
                secret: decodeSecret(uri: uri),
                algorithm: decodeAlgorithm(uri: uri),
                digits: decodeDigits(uri: uri),
                accountName: label.accountName,
                issuer: label.issuer,
            ),
        )
    }
}

// MARK: - Helpers

extension OTPAuthURIDecoder {
    private func decodeSecret(uri: URL) throws(Base32Error) -> OTPAuthSecret {
        guard let secret = uri.otpParameter(.secret) else {
            return .empty(.base32)
        }
        let data = try secret.base32DecodedData
        return .init(data: data, format: .base32)
    }

    private func decodeDigits(uri: URL) throws(URIDecodingError) -> OTPAuthDigits {
        guard let digits = uri.otpParameter(.digits) else {
            return .default
        }
        guard let value = UInt16(digits) else {
            throw URIDecodingError.invalidValue
        }
        return OTPAuthDigits(value: value)
    }

    private func decodeAlgorithm(uri: URL) throws(URIDecodingError) -> OTPAuthAlgorithm {
        guard let algorithm = uri.otpParameter(.algorithm) else {
            return .default
        }
        switch algorithm {
        case "SHA1":
            return .sha1
        case "SHA256":
            return .sha256
        case "SHA512":
            return .sha512
        default:
            throw URIDecodingError.invalidAlgorithm
        }
    }

    private func decodeLabel(uri: URL) throws(URIDecodingError) -> (accountName: String, issuer: String) {
        guard uri.pathComponents.count > 1 else {
            throw URIDecodingError.invalidLabel
        }
        let label = uri.pathComponents[1]
        let parts = label.split(separator: ":")
        guard let accountName = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw URIDecodingError.invalidLabel
        }
        var issuer = uri.otpParameter(.issuer)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if issuer.isEmpty, parts.count > 1 {
            issuer = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return (String(accountName), issuer)
    }

    private func decodeType(uri: URL) throws(URIDecodingError) -> OTPAuthType {
        guard let host = uri.host else {
            throw URIDecodingError.invalidType
        }
        switch host {
        case "totp":
            if let periodString = uri.otpParameter(.period), let period = UInt64(periodString) {
                guard OTPAuthType.TOTP.validPeriods.contains(period) else { throw URIDecodingError.invalidValue }
                return .totp(period: period)
            } else {
                return .totp()
            }
        case "hotp":
            if let counterStr = uri.otpParameter(.counter), let count = UInt64(counterStr) {
                guard OTPAuthType.HOTP.validCounters.contains(count) else { throw URIDecodingError.invalidValue }
                return .hotp(counter: count)
            } else {
                return .hotp()
            }
        default:
            throw URIDecodingError.invalidType
        }
    }
}

extension URL {
    func otpParameter(_ parameter: OTPAuthURI.Parameter) -> String? {
        queryParameters[parameter.rawValue]
    }
}
