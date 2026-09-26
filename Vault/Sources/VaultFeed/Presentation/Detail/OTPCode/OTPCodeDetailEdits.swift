import Foundation
import FoundationExtensions
import VaultCore

/// Encapsulates the edit state for a given code.
///
/// This is a partial edit to the code, as seen from the user's point of view.
/// Fields are separated from the raw model type to make them easier to edit in place.
/// From this model, they are merged with an existing model or written to a new model, as needed.
public struct OTPCodeDetailEdits: DetailEditorEditableState, Sendable {
    public var relativeOrder: UInt64

    public var codeType: OTPAuthType.Kind

    /// Only used for TOTP type codes, ignored otherwise
    public var totpPeriodLength: UInt64

    /// Only used for HOTP type codes, ignored otherwise
    public var hotpCounterValue: UInt64

    @FieldValidated(validationLogic: .otpSecretBase32)
    public var secretBase32String: String = ""

    public var algorithm: OTPAuthAlgorithm

    public var numberOfDigits: UInt16

    @FieldValidated(validationLogic: .stringRequiringContent)
    public var issuerTitle: String = ""

    public var accountNameTitle: String

    public var description: String

    public var viewConfig: VaultItemViewConfiguration

    /// Plaintext entered by the user when setting or replacing the search
    /// passphrase. Always blank on screen-open. Sent to the digester and
    /// then discarded before persistence.
    @FieldValidated(validationLogic: .stringRequiringContent)
    public var searchPassphrase: String = ""

    /// Whether this item already has a stored search-passphrase digest.
    /// Lets the edit form treat a blank `searchPassphrase` field as "keep
    /// the existing value" rather than "clear it", mirroring the
    /// killphrase behavior. The plaintext is never surfaced.
    public var hasExistingSearchPassphrase: Bool = false

    /// Whether this item currently has, or should have, a killphrase set.
    /// The plaintext killphrase is never surfaced to the UI; this is the
    /// only handle the edit screen has on the existing state.
    public var killphraseEnabled: Bool = false

    /// Plaintext entered by the user when setting or replacing the
    /// killphrase. Always blank on screen-open. Sent to the digester and
    /// then discarded before persistence.
    public var newKillphrase: String = ""

    public var color: VaultItemColor?

    public var tags: Set<Identifier<VaultItemTag>>

    public var lockState: VaultItemLockState

    public var showInQuickType: Bool

    public init(
        codeType: OTPAuthType.Kind,
        relativeOrder: UInt64,
        totpPeriodLength: UInt64,
        hotpCounterValue: UInt64,
        secretBase32String: String,
        algorithm: OTPAuthAlgorithm,
        numberOfDigits: UInt16,
        issuerTitle: String,
        accountNameTitle: String,
        description: String,
        viewConfig: VaultItemViewConfiguration,
        searchPassphrase: String,
        hasExistingSearchPassphrase: Bool,
        killphraseEnabled: Bool,
        newKillphrase: String,
        tags: Set<Identifier<VaultItemTag>>,
        lockState: VaultItemLockState,
        color: VaultItemColor?,
        showInQuickType: Bool,
    ) {
        self.codeType = codeType
        self.relativeOrder = relativeOrder
        self.totpPeriodLength = totpPeriodLength
        self.hotpCounterValue = hotpCounterValue
        self.secretBase32String = secretBase32String
        self.algorithm = algorithm
        self.numberOfDigits = numberOfDigits
        self.issuerTitle = issuerTitle
        self.accountNameTitle = accountNameTitle
        self.description = description
        self.viewConfig = viewConfig
        self.searchPassphrase = searchPassphrase
        self.hasExistingSearchPassphrase = hasExistingSearchPassphrase
        self.killphraseEnabled = killphraseEnabled
        self.newKillphrase = newKillphrase
        self.tags = tags
        self.lockState = lockState
        self.color = color
        self.showInQuickType = showInQuickType
    }

    public init(
        hydratedFromCode code: OTPAuthCode,
        relativeOrder: UInt64,
        userDescription: String,
        color: VaultItemColor?,
        viewConfig: VaultItemViewConfiguration,
        searchPassphrase: String,
        hasExistingSearchPassphrase: Bool,
        killphraseEnabled: Bool,
        tags: Set<Identifier<VaultItemTag>>,
        lockState: VaultItemLockState,
        showInQuickType: Bool,
    ) {
        codeType = code.type.kind
        totpPeriodLength = switch code.type {
        case let .totp(period): period
        case .hotp: OTPAuthType.TOTP.defaultPeriod
        }
        hotpCounterValue = switch code.type {
        case let .hotp(counter): counter
        case .totp: OTPAuthType.HOTP.defaultCounter
        }
        secretBase32String = code.data.secret.base32EncodedString
        algorithm = code.data.algorithm
        numberOfDigits = code.data.digits.value
        issuerTitle = code.data.issuer
        accountNameTitle = code.data.accountName
        description = userDescription
        self.tags = tags
        self.viewConfig = viewConfig
        self.searchPassphrase = searchPassphrase
        self.hasExistingSearchPassphrase = hasExistingSearchPassphrase
        self.killphraseEnabled = killphraseEnabled
        newKillphrase = ""
        self.lockState = lockState
        self.color = color
        self.relativeOrder = relativeOrder
        self.showInQuickType = showInQuickType
    }

    /// Constructs an OTPAuthCode from the current state of the edits
    public func asOTPAuthCode() throws -> OTPAuthCode {
        let otpAuthType: OTPAuthType = switch codeType {
        case .totp: .totp(period: totpPeriodLength)
        case .hotp: .hotp(counter: hotpCounterValue)
        }
        let otpAuthSecret = try OTPAuthSecret.base32EncodedString(secretBase32String)
        let otpAuthCodeData = OTPAuthCodeData(
            secret: otpAuthSecret,
            algorithm: algorithm,
            digits: .init(value: numberOfDigits),
            accountName: accountNameTitle,
            issuer: issuerTitle,
        )
        return OTPAuthCode(
            type: otpAuthType,
            data: otpAuthCodeData,
        )
    }

    public var isValid: Bool {
        DetailEditorStep.allCases.allSatisfy(isComplete)
    }

    public func isComplete(_ step: DetailEditorStep) -> Bool {
        switch step {
        case .content: $secretBase32String.isValid
        case .details: $issuerTitle.isValid
        case .appearance: true
        case .security: isPassphraseValid && isKillphraseValid
        }
    }

    /// Takes the key, and the names if the code has any, from a code that's been scanned. Everything else is kept.
    public mutating func applyKey(from code: OTPAuthCode) {
        codeType = code.type.kind
        switch code.type {
        case let .totp(period): totpPeriodLength = period
        case let .hotp(counter): hotpCounterValue = counter
        }
        secretBase32String = code.data.secret.base32EncodedString
        algorithm = code.data.algorithm
        numberOfDigits = code.data.digits.value
        if code.data.issuer.isNotEmpty {
            issuerTitle = code.data.issuer
        }
        if code.data.accountName.isNotEmpty {
            accountNameTitle = code.data.accountName
        }
    }

    public var isPassphraseValid: Bool {
        switch viewConfig {
        case .requiresSearchPassphrase: hasExistingSearchPassphrase || $searchPassphrase.isValid
        default: true
        }
    }

    public var isKillphraseValid: Bool {
        // Blank entry is valid (means "keep existing" when enabled, or
        // "no killphrase" when disabled). Whitespace-only is rejected.
        newKillphrase.isEmpty || newKillphrase.isNotBlank
    }

    public var killphraseIsEnabled: Bool {
        killphraseEnabled
    }

    public var killphraseEnabledText: String {
        if killphraseEnabled {
            "Enabled"
        } else {
            "None"
        }
    }

    public var killphraseEnabledIcon: String {
        if killphraseEnabled {
            "bolt.badge.checkmark.fill"
        } else {
            "bolt"
        }
    }
}

// MARK: - Helpers

extension OTPCodeDetailEdits {
    /// Create an `OTPCodeDetailEdits` in a blank state with initial input values, for creation.
    /// All initial values are sensible defaults.
    ///
    /// Uses standards suggested by https://datatracker.ietf.org/doc/html/rfc6238
    public static func new() -> OTPCodeDetailEdits {
        .init(
            codeType: .totp,
            relativeOrder: .min,
            totpPeriodLength: OTPAuthType.TOTP.defaultPeriod,
            hotpCounterValue: OTPAuthType.HOTP.defaultCounter,
            secretBase32String: "",
            algorithm: OTPAuthAlgorithm.default,
            numberOfDigits: OTPAuthDigits.default.value,
            issuerTitle: "",
            accountNameTitle: "",
            description: "",
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            newKillphrase: "",
            tags: [],
            lockState: .notLocked,
            color: nil,
            showInQuickType: true,
        )
    }

    public static func new(hydratedFromCode code: OTPAuthCode) -> OTPCodeDetailEdits {
        .init(
            hydratedFromCode: code,
            relativeOrder: .min,
            userDescription: "",
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            tags: [],
            lockState: .notLocked,
            showInQuickType: true,
        )
    }
}
