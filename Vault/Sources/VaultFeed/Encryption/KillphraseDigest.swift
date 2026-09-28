import Foundation

/// One-way digest representing an item's killphrase.
///
/// Stored in place of the plaintext phrase. The digest is computed as
/// `HMAC-SHA256(K, salt || phrase)` where `K` is a key on the device's
/// keyring (see `KillphraseKeyStore`). Recovering the original phrase from
/// the digest is computationally infeasible without `K` and a candidate
/// phrase.
public struct KillphraseDigest: Equatable, Hashable, Sendable, Codable {
    /// Per-item random salt mixed into the HMAC input. Prevents cross-item
    /// brute-force parallelisation.
    public let salt: Data
    /// HMAC-SHA256 output over `salt || phrase`.
    public let digest: Data

    public init(salt: Data, digest: Data) {
        self.salt = salt
        self.digest = digest
    }
}
