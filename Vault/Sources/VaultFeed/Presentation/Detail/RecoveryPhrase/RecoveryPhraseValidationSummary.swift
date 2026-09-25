import Foundation
import VaultCore

/// How a recovery phrase compares against its standard, for display.
public struct RecoveryPhraseValidationSummary: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The words and checksum are valid.
        case valid
        /// Something is wrong with the words, they should be checked.
        case warning
        /// Not enough information to say either way.
        case neutral
    }

    public var kind: Kind
    public var title: String
    public var detail: String
    public var systemIconName: String
    /// Zero-based positions of words that aren't in the wordlist.
    public var unknownWordPositions: Set<Int>

    public init(
        validation: RecoveryPhraseValidation,
        standard: RecoveryPhraseStandard,
        wordCount: Int,
        locale: Locale = .current,
    ) {
        unknownWordPositions = Set(validation.unknownWordPositions)
        let wordCountText = localized(key: "recoveryPhraseValidation.wordCount.\(wordCount)")
        switch validation.status {
        case let .valid(detail):
            kind = .valid
            systemIconName = "checkmark.seal.fill"
            switch detail {
            case let .bip39(languages):
                title = localized(key: "recoveryPhraseValidation.valid.bip39.title")
                let languageNames = languages.map {
                    locale.localizedString(forIdentifier: $0.localeIdentifier) ?? $0.localeIdentifier
                }
                self.detail = (languageNames + [wordCountText]).joined(separator: " · ")
            case .slip39:
                title = localized(key: "recoveryPhraseValidation.valid.slip39.title")
                self.detail = wordCountText
            case let .electrum(seedType):
                title = localized(key: "recoveryPhraseValidation.valid.electrum.title")
                self.detail = [seedType.localizedTitle, wordCountText].joined(separator: " · ")
            case .monero:
                title = localized(key: "recoveryPhraseValidation.valid.monero.title")
                self.detail = wordCountText
            }
        case .unknownWords:
            kind = .warning
            systemIconName = "exclamationmark.triangle.fill"
            title = localized(key: "recoveryPhraseValidation.unknownWords.title")
            let numbers = validation.unknownWordPositions.map { $0 + 1 }
            if numbers.count == 1, let number = numbers.first {
                detail = localized(key: "recoveryPhraseValidation.unknownWords.single.\(number)")
            } else {
                let list = ListFormatter.localizedString(byJoining: numbers.map(String.init))
                detail = localized(key: "recoveryPhraseValidation.unknownWords.multiple.\(list)")
            }
        case .invalidChecksum:
            kind = .warning
            systemIconName = "exclamationmark.triangle.fill"
            title = localized(key: "recoveryPhraseValidation.invalidChecksum.title")
            detail = localized(key: "recoveryPhraseValidation.invalidChecksum.detail")
        case .malformed:
            kind = .warning
            systemIconName = "exclamationmark.triangle.fill"
            if standard == .monero {
                title = localized(key: "recoveryPhraseValidation.malformed.monero.title")
                detail = localized(key: "recoveryPhraseValidation.malformed.monero.detail")
            } else {
                title = localized(key: "recoveryPhraseValidation.malformed.slip39.title")
                detail = localized(key: "recoveryPhraseValidation.malformed.slip39.detail")
            }
        case .unsupportedWordCount:
            kind = .warning
            systemIconName = "exclamationmark.triangle.fill"
            title = localized(key: "recoveryPhraseValidation.unsupportedWordCount.title")
            detail = localized(key: "recoveryPhraseValidation.unsupportedWordCount.detail.\(wordCount)")
        case .incomplete:
            kind = .neutral
            systemIconName = "ellipsis.circle"
            title = localized(key: "recoveryPhraseValidation.incomplete.title")
            detail = localized(key: "recoveryPhraseValidation.incomplete.detail.\(wordCount)")
        case .notValidated:
            kind = .neutral
            systemIconName = "info.circle"
            title = localized(key: "recoveryPhraseValidation.notValidated.title")
            detail = standard.isValidated
                ? localized(key: "recoveryPhraseValidation.notValidated.unavailable.detail")
                : localized(key: "recoveryPhraseValidation.notValidated.detail")
        }
    }
}

// MARK: - Localization

extension RecoveryPhraseStandard {
    public var localizedTitle: String {
        switch self {
        case .bip39: localized(key: "recoveryPhraseStandard.bip39.title")
        case .slip39: localized(key: "recoveryPhraseStandard.slip39.title")
        case .electrum: localized(key: "recoveryPhraseStandard.electrum.title")
        case .monero: localized(key: "recoveryPhraseStandard.monero.title")
        case .other: localized(key: "recoveryPhraseStandard.other.title")
        }
    }

    public var localizedSubtitle: String {
        switch self {
        case .bip39: localized(key: "recoveryPhraseStandard.bip39.subtitle")
        case .slip39: localized(key: "recoveryPhraseStandard.slip39.subtitle")
        case .electrum: localized(key: "recoveryPhraseStandard.electrum.subtitle")
        case .monero: localized(key: "recoveryPhraseStandard.monero.subtitle")
        case .other: localized(key: "recoveryPhraseStandard.other.subtitle")
        }
    }
}

extension ElectrumSeedType {
    public var localizedTitle: String {
        switch self {
        case .standard: localized(key: "electrumSeedType.standard.title")
        case .segwit: localized(key: "electrumSeedType.segwit.title")
        case .twoFactor: localized(key: "electrumSeedType.twoFactor.title")
        case .twoFactorSegwit: localized(key: "electrumSeedType.twoFactorSegwit.title")
        }
    }
}
