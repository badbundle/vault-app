import CryptoKit
import Foundation
import FoundationExtensions

/// Computes and verifies one-way killphrase digests for a vault.
///
/// Digests are `HMAC-SHA256(K, salt || normalize(phrase))` where
/// `normalize(...)` trims surrounding whitespace and `K` is a 256-bit key
/// that lives in the device keychain (see `KillphraseKeyStore`). The same
/// `K` is reused across every item; per-item randomness comes from `salt`,
/// which is regenerated on every set.
public struct KillphraseDigester: KillphraseMatcher, Sendable {
    /// Random salt length, in bytes, generated per item.
    public static let saltLength = 16

    private let key: SymmetricKey

    public init(key: KeyData<32>) {
        self.key = SymmetricKey(data: key.data)
    }

    init(key: SymmetricKey) {
        self.key = key
    }

    /// Produce a digest for the given plaintext phrase, using a fresh random salt.
    public func makeDigest(phrase: String) -> KillphraseDigest {
        let salt = Data.random(count: Self.saltLength)
        let digest = computeDigest(phrase: Self.normalize(phrase), salt: salt)
        return KillphraseDigest(salt: salt, digest: digest)
    }

    /// Returns `true` iff `HMAC(K, salt || normalize(query))` equals `digest`.
    ///
    /// Uses CryptoKit's `isValidAuthenticationCode` which performs a
    /// constant-time comparison. Callers must not branch on this result in
    /// any externally observable way beyond performing the deletion itself.
    public func matches(query: String, salt: Data, digest: Data) -> Bool {
        var message = salt
        message.append(Data(Self.normalize(query).utf8))
        return HMAC<SHA256>.isValidAuthenticationCode(
            digest,
            authenticating: message,
            using: key,
        )
    }

    /// Both sides of the comparison must apply the same normalization or
    /// the HMAC will not match: digests have always been created from
    /// trimmed phrases, but the live search query arrives untrimmed, so a
    /// trailing space from the keyboard would silently stop a killphrase
    /// from firing. Trim only — no canonical/case fold, because existing
    /// digests were computed without one and killphrases are intentionally
    /// exact-match otherwise.
    static func normalize(_ phrase: String) -> String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func computeDigest(phrase: String, salt: Data) -> Data {
        var message = salt
        message.append(Data(phrase.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(mac)
    }
}
