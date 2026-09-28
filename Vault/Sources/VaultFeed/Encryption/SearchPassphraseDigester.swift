import CryptoKit
import Foundation
import FoundationExtensions

/// Computes and verifies one-way search-passphrase digests for a vault.
///
/// Digests are `HMAC-SHA256(K, salt || fold(phrase))` where `K` is a 256-bit
/// key that lives in the device keychain (see `SearchPassphraseKeyStore`)
/// and `fold(...)` is `precomposedStringWithCanonicalMapping` followed by
/// `folding(options: .caseInsensitive, locale: nil)`. The same `K` is
/// reused across every item; per-item randomness comes from `salt`, which
/// is regenerated on every set.
///
/// The case fold preserves the case-insensitive search behavior that the
/// prior plaintext `caseInsensitiveCompare` predicate provided.
///
/// New digests are always made with this device's own key. Matching also
/// tries the keys restored backups brought (`HMACKeyring`), which their
/// items' digests were made with.
public struct SearchPassphraseDigester: SearchPassphraseMatcher, Sendable {
    /// Random salt length, in bytes, generated per item.
    public static let saltLength = 16

    private let key: SymmetricKey
    /// This device's own key, then the keys from backups.
    private let keyring: [SymmetricKey]

    public init(key: KeyData<32>, keysFromBackups: [KeyData<32>] = []) {
        self.key = SymmetricKey(data: key.data)
        keyring = [self.key] + keysFromBackups.map { SymmetricKey(data: $0.data) }
    }

    init(key: SymmetricKey) {
        self.key = key
        keyring = [key]
    }

    /// Produce a digest for the given plaintext phrase, using a fresh random salt.
    public func makeDigest(phrase: String) -> SearchPassphraseDigest {
        let salt = Data.random(count: Self.saltLength)
        let digest = computeDigest(folded: Self.fold(phrase), salt: salt)
        return SearchPassphraseDigest(salt: salt, digest: digest)
    }

    /// Returns `true` iff `HMAC(K, salt || fold(query))` equals `digest` for
    /// any key `K` on the keyring.
    ///
    /// Every key is tried with CryptoKit's `isValidAuthenticationCode`, for
    /// constant-time comparison, whichever matches.
    public func matches(query: String, salt: Data, digest: Data) -> Bool {
        var message = salt
        message.append(Data(Self.fold(query).utf8))
        return HMACKeyring.anyKey(of: keyring, authenticates: digest, message: message)
    }

    /// Canonicalize then case-fold. Both sides of the comparison must
    /// apply the same fold or the HMAC will not match even for inputs
    /// that the prior `caseInsensitiveCompare` predicate would have
    /// treated as equal.
    static func fold(_ phrase: String) -> String {
        phrase
            .precomposedStringWithCanonicalMapping
            .folding(options: .caseInsensitive, locale: nil)
    }

    private func computeDigest(folded: String, salt: Data) -> Data {
        var message = salt
        message.append(Data(folded.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(mac)
    }
}
