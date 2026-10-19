import Foundation

/// Model type for a private key: a crypto wallet's single key, such as a WIF key, an extended private key (xprv) or a
/// Nostr `nsec`, or a PGP or SSH private key.
///
/// Like a recovery phrase, a private key is only ever persisted inside an encrypted item, so this plaintext form should
/// only exist in memory after the user has decrypted it. Vault never derives anything from it: no public key and no
/// address.
public struct PrivateKey: Equatable, Hashable, Sendable {
    /// User-visible title. This is stored in plaintext alongside the encrypted item, so is visible without the
    /// password.
    public var title: String
    /// The key, as it was entered: a single line, such as a WIF key, or a block of lines, such as an OpenSSH key.
    ///
    /// Kept exactly as entered, apart from whitespace around it, and inside a single-line key that's only valid once
    /// it's removed (`PrivateKeyValidation.canonicalKey`), as a wallet wouldn't accept it otherwise.
    public var key: String
    /// Freeform description shown below the title, for context such as which wallet or account the key is for (like
    /// the contents of a `SecureNote`). Encrypted along with the key, unlike the title.
    public var contents: String

    public init(title: String, key: String, contents: String = "") {
        self.title = title
        self.key = key
        self.contents = contents
    }
}

// MARK: - Redaction

// The key and description must never end up in a log, crash report or test failure message via string interpolation
// or reflection, so all textual representations are redacted.

extension PrivateKey: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "PrivateKey(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [], displayStyle: .struct)
    }
}
