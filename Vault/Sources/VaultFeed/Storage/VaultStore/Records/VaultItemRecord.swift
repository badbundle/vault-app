import Foundation

/// A stored vault item as plain values: every field of `PersistedVaultItem` and its detail relationships, in the
/// raw form they're persisted in.
///
/// Records sit between the domain model and storage. `PersistedVaultItemEncoder` turns a `VaultItem.Write` into a
/// record and `PersistedVaultItemDecoder` turns a record back into a `VaultItem`, so every store shares the same
/// encoding. The SwiftData store copies records to and from its `@Model` objects.
///
/// A record mirrors the latest persisted schema field for field, and deliberately holds values that may not
/// decode: an unknown algorithm, no detail at all, or more than one. Copying records between stores can never
/// drop or change an item, even one that only shows up as a decoding error. `VaultRecordSchemaParityTests` fail
/// if the schema gains a field the record doesn't carry.
///
/// An encrypted vault stores its records as JSON (`EncryptedVaultPayload`), keyed by these property names, so
/// renaming a property changes the file format.
struct VaultItemRecord: Codable, Equatable, Sendable {
    var id: UUID
    var relativeOrder: UInt64
    var createdDate: Date
    var updatedDate: Date
    var userDescription: String
    /// One of `VaultEncodingConstants.Visibility`.
    var visibility: String
    /// One of `VaultEncodingConstants.SearchableLevel`.
    var searchableLevel: String
    var searchPassphraseSalt: Data?
    var searchPassphraseDigest: Data?
    var killphraseSalt: Data?
    var killphraseDigest: Data?
    /// One of `VaultEncodingConstants.LockState`, or `nil` for items stored before lock states existed.
    var lockState: String?
    var color: PersistedColor?
    var showInQuickType: Bool
    /// A `NotePreviewMode` raw value.
    var previewMode: String
    /// The ids of the item's tags.
    ///
    /// Stores only keep ids of tags that exist: writing a record that names a missing tag stores the item without
    /// it, as it always has.
    var tagIDs: Set<UUID>
    var noteDetails: NoteDetails?
    var otpDetails: OTPDetails?
    var encryptedItemDetails: EncryptedItemDetails?
}

extension VaultItemRecord {
    /// Mirrors `PersistedNoteDetails`.
    struct NoteDetails: Codable, Equatable, Sendable {
        var title: String
        var contents: String
        /// One of `VaultEncodingConstants.TextFormat`.
        var format: String
    }

    /// Mirrors `PersistedOTPDetails`.
    struct OTPDetails: Codable, Equatable, Sendable {
        var accountName: String
        var issuer: String
        /// One of `VaultEncodingConstants.OTPAuthAlgorithm`.
        var algorithm: String
        /// One of `VaultEncodingConstants.OTPAuthType`.
        var authType: String
        /// Set for HOTP codes.
        var counter: Int64?
        var digits: Int32
        /// Set for TOTP codes.
        var period: Int64?
        var secretData: Data
        /// One of `VaultEncodingConstants.OTPAuthSecret.Format`.
        var secretFormat: String
    }

    /// Mirrors `PersistedEncryptedItemDetails`.
    struct EncryptedItemDetails: Codable, Equatable, Sendable {
        var version: String
        var title: String
        var data: Data
        var authentication: Data
        var encryptionIV: Data
        var keygenSalt: Data
        var keygenSignature: String
    }
}
