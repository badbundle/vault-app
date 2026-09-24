import Foundation
import FoundationExtensions
import VaultCore
import VaultKeygen

/// Encapsulates editing state for a recovery phrase.
///
/// A recovery phrase is always encrypted and always locked, so unlike other items there's no way to turn either
/// off: the edits are only valid once there's a password, and the lock state is fixed.
public struct RecoveryPhraseDetailEdits: EditableState {
    public var relativeOrder: UInt64

    /// Stored in plaintext, alongside the encrypted item.
    public var title: String

    /// Freeform description shown below the title, encrypted along with the words.
    public var contents: String

    public private(set) var standard: RecoveryPhraseStandard

    /// The words, as entered. Always `wordCount` long, with blanks for words that haven't been entered yet.
    public private(set) var words: [String]

    /// The optional passphrase (25th word, seed extension). Kept exactly as entered, never trimmed: any change,
    /// even to whitespace, derives a different wallet.
    public var seedPassphrase: String

    public var viewConfig: VaultItemViewConfiguration

    /// Plaintext entered by the user when setting or replacing the search
    /// passphrase. Always blank on screen-open. Sent to the digester and
    /// then discarded before persistence.
    @FieldValidated(validationLogic: .stringRequiringContent)
    public var searchPassphrase: String = ""

    /// Whether this item already has a stored search-passphrase digest.
    public var hasExistingSearchPassphrase: Bool = false

    /// Whether this item currently has, or should have, a killphrase set.
    public var killphraseEnabled: Bool = false

    /// Plaintext entered by the user when setting or replacing the
    /// killphrase. Always blank on screen-open.
    public var newKillphrase: String = ""

    /// Set when the user has chosen a new password. A key will be derived from it, replacing `existingEncryptionKey`.
    public var newEncryptionPassword: String = ""

    /// The key the item is currently encrypted with, used to re-encrypt it when there's no new password.
    public var existingEncryptionKey: DerivedEncryptionKey?

    public var color: VaultItemColor?

    public var tags: Set<Identifier<VaultItemTag>>

    public var previewMode: NotePreviewMode

    public init(
        title: String,
        contents: String,
        standard: RecoveryPhraseStandard,
        words: [String],
        seedPassphrase: String,
        color: VaultItemColor?,
        viewConfig: VaultItemViewConfiguration,
        searchPassphrase: String,
        hasExistingSearchPassphrase: Bool,
        killphraseEnabled: Bool,
        newKillphrase: String,
        tags: Set<Identifier<VaultItemTag>>,
        relativeOrder: UInt64,
        existingEncryptionKey: DerivedEncryptionKey?,
        previewMode: NotePreviewMode,
    ) {
        self.title = title
        self.contents = contents
        self.standard = standard
        self.words = words
        self.seedPassphrase = seedPassphrase
        self.color = color
        self.viewConfig = viewConfig
        self.searchPassphrase = searchPassphrase
        self.hasExistingSearchPassphrase = hasExistingSearchPassphrase
        self.killphraseEnabled = killphraseEnabled
        self.newKillphrase = newKillphrase
        self.tags = tags
        self.relativeOrder = relativeOrder
        self.existingEncryptionKey = existingEncryptionKey
        self.previewMode = previewMode
    }

    public var isValid: Bool {
        isEncrypted && hasAllWords && isSearchPassphraseValid
    }

    /// Recovery phrases are always locked, this can't be changed.
    public var lockState: VaultItemLockState {
        .lockedWithNativeSecurity
    }

    public var wordCount: Int {
        words.count
    }

    /// Every word has been entered, and there's a supported number of them.
    ///
    /// This doesn't mean that the words are valid: an invalid phrase can still be saved.
    public var hasAllWords: Bool {
        standard.supports(wordCount: words.count) && words.allSatisfy(\.isNotBlank)
    }

    /// How the words compare against the standard's wordlist and checksum.
    public var validation: RecoveryPhraseValidation {
        RecoveryPhraseValidator.validate(words: words, standard: standard)
    }

    public var isSearchPassphraseValid: Bool {
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

    public var killphraseEnabledText: String {
        killphraseEnabled ? "Enabled" : "None"
    }

    public var isEncrypted: Bool {
        newEncryptionPassword.isNotBlank || existingEncryptionKey.isNotNil
    }

    public var passwordState: PasswordState {
        if newEncryptionPassword.isNotBlank {
            existingEncryptionKey == nil ? .set : .willChange
        } else {
            existingEncryptionKey == nil ? .required : .set
        }
    }

    public enum PasswordState: Equatable, Sendable {
        /// No password yet, so the item can't be saved.
        case required
        case set
        /// The item will be re-encrypted with a new password when saved.
        case willChange
    }

    /// Leading or trailing whitespace in the passphrase is almost always a mistake, but it can't be removed
    /// automatically as it changes the wallet.
    public var seedPassphraseHasSurroundingWhitespace: Bool {
        guard let first = seedPassphrase.first, let last = seedPassphrase.last else { return false }
        return first.isWhitespace || last.isWhitespace
    }
}

// MARK: - Editing

extension RecoveryPhraseDetailEdits {
    /// Changes the standard, resizing the words to the nearest word count it supports.
    public mutating func setStandard(_ newStandard: RecoveryPhraseStandard) {
        standard = newStandard
        setWordCount(words.count)
    }

    /// Resizes the words, keeping those already entered. `count` is clamped to one the standard supports.
    public mutating func setWordCount(_ count: Int) {
        let supportedCount = standard.supports(wordCount: count) ? count : standard.nearestSupportedWordCount(to: count)
        if supportedCount < words.count {
            words.removeLast(words.count - supportedCount)
        } else if supportedCount > words.count {
            words.append(contentsOf: Array(repeating: "", count: supportedCount - words.count))
        }
    }

    /// Applies text entered into the field for the word at `position`.
    ///
    /// Plain typing is kept exactly as entered. Text containing whitespace, typically pasted, is split into words
    /// that fill this and the following positions. Pasting a whole phrase into the first word resizes the phrase to
    /// fit, if the standard supports that many words.
    ///
    /// - Returns: The position to move to next, if the input has completed this word.
    @discardableResult
    public mutating func applyInput(_ text: String, at position: Int) -> Int? {
        guard words.indices.contains(position) else { return nil }
        guard RecoveryPhraseInput.containsSeparator(text) else {
            words[position] = text
            return nil
        }

        let entered = RecoveryPhraseInput.words(in: text)
        guard entered.isNotEmpty else {
            words[position] = ""
            return nil
        }
        if position == 0, entered.count != words.count, standard.supports(wordCount: entered.count) {
            setWordCount(entered.count)
        }
        for (offset, word) in entered.prefix(words.count - position).enumerated() {
            words[position + offset] = word
        }
        let next = position + entered.count
        return next < words.count ? next : nil
    }

    /// The phrase to save.
    public func makeRecoveryPhrase() -> RecoveryPhrase {
        let trimmedWords = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return RecoveryPhrase(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            // When the phrase is valid, save it as spelled in the wordlist (with any accents that were omitted when
            // typing) as that's the form a wallet will accept.
            words: validation.canonicalWords ?? trimmedWords,
            standard: standard,
            passphrase: seedPassphrase,
            contents: contents.trimmingCharacters(in: .whitespacesAndNewlines),
        )
    }
}

// MARK: - Helpers

extension RecoveryPhraseDetailEdits {
    /// Create an `RecoveryPhraseDetailEdits` in a blank state with initial input values, for creation.
    public static func new() -> RecoveryPhraseDetailEdits {
        let standard = RecoveryPhraseStandard.bip39
        return .init(
            title: "",
            contents: "",
            standard: standard,
            words: Array(repeating: "", count: standard.defaultWordCount),
            seedPassphrase: "",
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            newKillphrase: "",
            tags: [],
            relativeOrder: .min,
            existingEncryptionKey: nil,
            // Only the title: the contents of an encrypted item are never previewed.
            previewMode: .titleOnly,
        )
    }
}
