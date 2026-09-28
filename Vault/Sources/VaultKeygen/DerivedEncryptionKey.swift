import CryptoEngine
import Foundation
import FoundationExtensions

public struct DerivedEncryptionKey: Equatable, Hashable, Sendable {
    /// The derived key (via keygen) from the user's password.
    /// (We don't store the password, only the derived key).
    public var key: KeyData<32>
    /// The salt used in the keygen process to derive `key`.
    public var salt: Data
    /// The keygen that was used to derive this password.
    public var keyDervier: VaultKeyDeriver.Signature

    public init(key: KeyData<32>, salt: Data, keyDervier: VaultKeyDeriver.Signature) {
        self.key = key
        self.salt = salt
        self.keyDervier = keyDervier
    }
}

// MARK: - Redaction

// The key must never end up in a log, crash report or test failure message via string interpolation or reflection, so
// all textual representations leave it out.

extension DerivedEncryptionKey: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "DerivedEncryptionKey(<redacted>, keyDeriver: \(keyDervier.rawValue))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["keyDeriver": keyDervier.rawValue], displayStyle: .struct)
    }
}

// MARK: - Keygen

extension DerivedEncryptionKey {
    public func newVaultKeyWithRandomIV() throws -> VaultKey {
        .init(key: key, iv: .random())
    }
}
