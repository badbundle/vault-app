import Foundation
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

struct OTPCodeDetailEditsTests {
    @Test
    func initHydratedFromCode_assignsTOTPCodeType() {
        let code = OTPAuthCode(
            type: .totp(period: 1234),
            data: .init(
                secret: makeExampleSecret(),
                algorithm: .sha1,
                digits: .default,
                accountName: "myacc",
                issuer: "myiss",
            ),
        )

        let color = VaultItemColor(red: 0.1, green: 0.3, blue: 0.4)
        let sut = OTPCodeDetailEdits(
            hydratedFromCode: code,
            relativeOrder: 1234,
            userDescription: "mydesc",
            color: color,
            viewConfig: .alwaysVisible,
            searchPassphrase: "search",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: true,
            tags: [],
            lockState: .lockedWithNativeSecurity,
            showInQuickType: true,
        )

        #expect(sut.codeType == .totp)
        #expect(sut.totpPeriodLength == 1234)
        #expect(sut.hotpCounterValue == 0) // Defaults HOTP to default for TOTP code
        #expect(sut.algorithm == .sha1)
        #expect(sut.numberOfDigits == 6)
        #expect(sut.issuerTitle == "myiss")
        #expect(sut.accountNameTitle == "myacc")
        #expect(sut.description == "mydesc")
        #expect(sut.color == color)
        #expect(sut.secretBase32String == "V6X27LY=")
        #expect(sut.viewConfig == .alwaysVisible)
        #expect(sut.searchPassphrase == "search")
        #expect(sut.killphraseEnabled == true)
        #expect(sut.lockState == .lockedWithNativeSecurity)
        #expect(sut.relativeOrder == 1234)
    }

    @Test
    func initHydratedFromCode_assignsHOTPCodeType() {
        let code = OTPAuthCode(
            type: .hotp(counter: 12345),
            data: .init(
                secret: makeExampleSecret(),
                algorithm: .sha256,
                digits: .default,
                accountName: "myacc2",
                issuer: "myiss2",
            ),
        )

        let color = VaultItemColor(red: 0.1, green: 0.3, blue: 0.4)
        let sut = OTPCodeDetailEdits(
            hydratedFromCode: code,
            relativeOrder: 4321,
            userDescription: "mydesc2",
            color: color,
            viewConfig: .alwaysVisible,
            searchPassphrase: "search",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: true,
            tags: [],
            lockState: .lockedWithNativeSecurity,
            showInQuickType: true,
        )

        #expect(sut.codeType == .hotp)
        #expect(sut.totpPeriodLength == 30) // Defaults TOTP to default for HOTP code
        #expect(sut.hotpCounterValue == 12345)
        #expect(sut.algorithm == .sha256)
        #expect(sut.numberOfDigits == 6)
        #expect(sut.issuerTitle == "myiss2")
        #expect(sut.accountNameTitle == "myacc2")
        #expect(sut.description == "mydesc2")
        #expect(sut.color == color)
        #expect(sut.secretBase32String == "V6X27LY=")
        #expect(sut.viewConfig == .alwaysVisible)
        #expect(sut.searchPassphrase == "search")
        #expect(sut.killphraseEnabled == true)
        #expect(sut.lockState == .lockedWithNativeSecurity)
        #expect(sut.relativeOrder == 4321)
    }

    @Test
    func init_emptySecretIsEmptySecretBase32String() {
        let code = anyOTPAuthCode(secret: .empty())

        let sut = OTPCodeDetailEdits(
            hydratedFromCode: code,
            relativeOrder: .min,
            userDescription: "mydesc",
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            tags: [],
            lockState: .notLocked,
            showInQuickType: true,
        )

        #expect(sut.secretBase32String == "")
    }

    @Test
    func isValid_validSecretIsValid() {
        let code = anyOTPAuthCode(secret: makeExampleSecret())

        let sut = OTPCodeDetailEdits(
            hydratedFromCode: code,
            relativeOrder: .min,
            userDescription: "mydesc2",
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            tags: [],
            lockState: .notLocked,
            showInQuickType: true,
        )

        #expect(sut.isValid)
    }

    @Test
    func isValid_invalidForEmptySecret() {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())
        sut.secretBase32String = ""

        #expect(!sut.isValid)
    }

    @Test
    func isValid_invalidForEmptyIssuer() {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())
        sut.issuerTitle = ""

        #expect(!sut.isValid)
    }

    @Test
    func isValid_invalidSecretIsInvalid() {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())
        sut.secretBase32String = "A" // this is invalid

        #expect(!sut.isValid)
    }

    @Test
    func isValid_invalidForEmptyPassphrase() {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())
        sut.searchPassphrase = ""
        sut.viewConfig = .requiresSearchPassphrase

        #expect(!sut.isValid)
    }

    @Test
    func isValid_validForNonEmptyPassphrase() {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())
        sut.secretBase32String = "AA"
        sut.issuerTitle = "any"
        sut.searchPassphrase = "passphrase"
        sut.viewConfig = .requiresSearchPassphrase

        #expect(sut.isValid)
    }

    @Test
    func asOTPAuthCode_createsTOTPCode() throws {
        let code = anyTOTPAuthCode()
        let sut = OTPCodeDetailEdits(
            hydratedFromCode: code,
            relativeOrder: .min,
            userDescription: "mydesc",
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            tags: [],
            lockState: .notLocked,
            showInQuickType: true,
        )

        let newCode = try sut.asOTPAuthCode()

        #expect(code == newCode)
    }

    @Test
    func asOTPAuthCode_createsHOTPCode() throws {
        let code = anyHOTPAuthCode()
        let sut = OTPCodeDetailEdits(
            hydratedFromCode: code,
            relativeOrder: .min,
            userDescription: "mydesc2",
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            tags: [],
            lockState: .notLocked,
            showInQuickType: true,
        )

        let newCode = try sut.asOTPAuthCode()

        #expect(code == newCode)
    }

    @Test
    func asOTPAuthCode_throwsErrorIfBase32SecretIsInvalid() throws {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())
        sut.secretBase32String = "e~~"

        #expect(throws: (any Error).self) {
            try sut.asOTPAuthCode()
        }
    }

    @Test
    func isValid_validWhenExistingSearchPassphraseRequiresBlankPassphrase() {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())
        sut.secretBase32String = "AA"
        sut.issuerTitle = "issuer"
        sut.viewConfig = .requiresSearchPassphrase
        sut.hasExistingSearchPassphrase = true
        sut.searchPassphrase = ""

        #expect(sut.isValid)
    }

    @Test
    func killphrasePropertiesReflectEnabledState() {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())

        #expect(sut.killphraseIsEnabled == false)
        #expect(sut.killphraseEnabledText == "None")
        #expect(sut.killphraseEnabledIcon == "bolt")

        sut.killphraseEnabled = true

        #expect(sut.killphraseIsEnabled)
        #expect(sut.killphraseEnabledText == "Enabled")
        #expect(sut.killphraseEnabledIcon == "bolt.badge.checkmark.fill")
    }

    @Test
    func isKillphraseValid_rejectsWhitespaceOnlyValue() {
        var sut = OTPCodeDetailEdits.new(defaults: NewItemDefaults())

        sut.newKillphrase = ""
        #expect(sut.isKillphraseValid)

        sut.newKillphrase = "phrase"
        #expect(sut.isKillphraseValid)

        sut.newKillphrase = "   "
        #expect(sut.isKillphraseValid == false)
    }
}

// MARK: - Helpers

extension OTPCodeDetailEditsTests {
    private func makeExampleSecret() -> OTPAuthSecret {
        OTPAuthSecret(data: Data(hex: "afafafaf"), format: .base32)
    }

    private func anyOTPAuthCode(secret: OTPAuthSecret) -> OTPAuthCode {
        OTPAuthCode(
            type: .totp(period: 1234),
            data: .init(secret: secret, algorithm: .sha1, digits: .default, accountName: "myacc", issuer: "myiss"),
        )
    }

    private func anyTOTPAuthCode() -> OTPAuthCode {
        OTPAuthCode(
            type: .totp(period: 1234),
            data: .init(
                secret: makeExampleSecret(),
                algorithm: .sha1,
                digits: .default,
                accountName: "myacc",
                issuer: "myiss",
            ),
        )
    }

    private func anyHOTPAuthCode() -> OTPAuthCode {
        OTPAuthCode(
            type: .hotp(counter: 12345),
            data: .init(
                secret: makeExampleSecret(),
                algorithm: .sha256,
                digits: .default,
                accountName: "myacc2",
                issuer: "myiss2",
            ),
        )
    }
}
