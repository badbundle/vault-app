import Foundation

/// Model type for a recovery phrase (the seed words for a crypto wallet).
///
/// A recovery phrase is only ever persisted inside an encrypted item, so this plaintext form should only exist in
/// memory after the user has decrypted it.
public struct RecoveryPhrase: Equatable, Hashable, Sendable {
    /// User-visible title. This is stored in plaintext alongside the encrypted item, so is visible without the
    /// password.
    public var title: String
    /// The words of the phrase, in order.
    public var words: [String]
    /// Freeform description shown below the title, for context such as which wallet or account the phrase is for
    /// (like the contents of a `SecureNote`). Encrypted along with the words, unlike the title.
    public var contents: String
    /// The standard that the words are expected to conform to, used for validation.
    public var standard: RecoveryPhraseStandard
    /// The optional passphrase (also known as the "25th word" or seed extension).
    ///
    /// This is kept exactly as it was entered: any change to it, even whitespace, results in a different wallet.
    /// Empty if there is no passphrase.
    public var passphrase: String

    public init(
        title: String,
        words: [String],
        standard: RecoveryPhraseStandard,
        passphrase: String,
        contents: String = "",
    ) {
        self.title = title
        self.words = words
        self.contents = contents
        self.standard = standard
        self.passphrase = passphrase
    }
}

// MARK: - Redaction

// The words, passphrase and description must never end up in a log, crash report or test failure message via string
// interpolation or reflection, so all textual representations are redacted.

extension RecoveryPhrase: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "RecoveryPhrase(<redacted>, \(words.count) words)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["wordCount": words.count], displayStyle: .struct)
    }
}
