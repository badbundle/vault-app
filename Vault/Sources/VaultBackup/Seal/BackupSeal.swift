import CryptoKit
import Foundation

/// A backup's seal: a picture (`BackupSealArtwork`) and a short code, both worked out from the backup's encrypted
/// bytes.
///
/// Every copy of a backup has the same seal, and two backups almost never do, so the seal printed on a PDF backup
/// matches the one Check a Backup shows when that backup opens, and tells copies of different backups apart.
///
/// - It comes from the backup as it's stored, encrypted, never from what it holds, so it says nothing about what's in
///   it. Backing up the same items twice gives two seals, as each backup is encrypted afresh.
/// - Vault doesn't keep seals anywhere: one is worked out again each time it's shown.
/// - Hashing isn't encryption, so it doesn't change Vault's export compliance (`docs/export-compliance.md`).
///
/// The digest is SHA-256 over a fixed tag, then each of the backup's fields as a big-endian 64-bit length followed by
/// its bytes. Seals are printed on paper that has to keep matching, so this never changes: `BackupSealTests` pins it.
public struct BackupSeal: Equatable, Hashable, Sendable {
    /// The 32 bytes of the SHA-256 digest everything about the seal is drawn from.
    public let digest: [UInt8]

    public init(encryptedVault: EncryptedVault) {
        var hasher = SHA256()
        hasher.update(data: Data(Self.domainTag.utf8))
        let version = encryptedVault.version
        let fields: [Data] = [
            Data("\(version.major).\(version.minor).\(version.patch)".utf8),
            encryptedVault.data,
            encryptedVault.authentication,
            encryptedVault.encryptionIV,
            encryptedVault.keygenSalt,
            Data(encryptedVault.keygenSignature.utf8),
        ]
        for field in fields {
            withUnsafeBytes(of: UInt64(field.count).bigEndian) { hasher.update(bufferPointer: $0) }
            hasher.update(data: field)
        }
        self.init(digest: Array(hasher.finalize()))
    }

    /// A seal with this digest, for previews and tests.
    init(digest: [UInt8]) {
        precondition(digest.count == 32, "A seal's digest is 32 bytes")
        self.digest = digest
    }

    /// Kept apart from any other SHA-256 Vault works out.
    private static let domainTag = "vault.backup.seal.v1"

    /// The seal's code, such as `E2DB-M504`: the digest's first 40 bits in Crockford's base 32, which has no I, L, O
    /// or U, so it can be read out and typed without mixing up letters and digits.
    public var code: String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let bits = digest.prefix(5).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let characters = (0 ..< 8).reversed().map { alphabet[Int((bits >> UInt64($0 * 5)) & 31)] }
        return String(characters[0 ..< 4]) + "-" + String(characters[4 ..< 8])
    }

    /// The code as VoiceOver should read it: one character at a time, with a pause at the dash.
    public var spokenCode: String {
        code.split(separator: "-")
            .map { $0.map(String.init).joined(separator: " ") }
            .joined(separator: ", ")
    }
}
