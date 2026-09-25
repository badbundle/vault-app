import Foundation
import FoundationExtensions

/// A full backup of the user's vault.
///
/// This is currently a "version 1" vault backup. It must be maintained for future compatibility in the event that
/// this structure is changed in the future.
public struct VaultBackupPayload: Codable, Equatable {
    /// Version of this backup, determined when the backup was initially created.
    ///
    /// Determines the decoding structure. This allows for future breaking changes.
    public var version: SemVer
    /// The date that the backup was created.
    public var created: Date
    /// Custom user provided desciption attached to the backup.
    public var userDescription: String
    /// The tags that are used to group item.
    public var tags: [VaultBackupTag]
    /// The individual items from the vault.
    public var items: [VaultBackupItem]
    /// Arbitrary padding used to disguise the actual size of the payload.
    /// This is a security requirement as users may have hidden items in their vault.
    ///
    /// This should be sufficient to disguise the number of items in the payload, but not
    /// so large to make the payload hard to handle.
    var obfuscationPadding: Data
}

// MARK: - Tag

public struct VaultBackupTag: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var color: VaultBackupRGBColor?
    public var iconName: String?

    public init(id: UUID, title: String, color: VaultBackupRGBColor?, iconName: String?) {
        self.id = id
        self.title = title
        self.color = color
        self.iconName = iconName
    }
}

// MARK: - Item

public struct VaultBackupItem: Codable, Equatable, Identifiable {
    /// The underlying ID of the vault item in the application.
    public var id: UUID
    public var createdDate: Date
    public var updatedDate: Date
    public var relativeOrder: UInt64
    public var userDescription: String
    public var tags: Set<UUID>
    public var visibility: Visibility
    public var searchableLevel: SearchableLevel
    /// Per-item random salt for the search-passphrase HMAC. Paired with
    /// `searchPassphraseDigest`; both are `nil` when no passphrase is set.
    public var searchPassphraseSalt: Data?
    /// HMAC-SHA256 of `searchPassphraseSalt || fold(phrase)`.
    public var searchPassphraseDigest: Data?
    /// Per-item random salt for the killphrase HMAC. Paired with
    /// `killphraseDigest`; both are `nil` when no killphrase is set.
    public var killphraseSalt: Data?
    /// HMAC-SHA256 of `killphraseSalt || phrase`.
    public var killphraseDigest: Data?
    public var lockState: LockState
    /// The tint color associated with the item.
    public var tintColor: VaultBackupRGBColor?
    /// The item's data that is used to reconstruct the item.
    public var item: Item

    public init(
        id: UUID,
        createdDate: Date,
        updatedDate: Date,
        relativeOrder: UInt64,
        userDescription: String,
        tags: Set<UUID>,
        visibility: Visibility,
        searchableLevel: SearchableLevel,
        searchPassphraseSalt: Data?,
        searchPassphraseDigest: Data?,
        killphraseSalt: Data?,
        killphraseDigest: Data?,
        lockState: LockState,
        tintColor: VaultBackupRGBColor? = nil,
        item: Item,
    ) {
        self.id = id
        self.createdDate = createdDate
        self.updatedDate = updatedDate
        self.relativeOrder = relativeOrder
        self.userDescription = userDescription
        self.tags = tags
        self.visibility = visibility
        self.searchableLevel = searchableLevel
        self.searchPassphraseSalt = searchPassphraseSalt
        self.searchPassphraseDigest = searchPassphraseDigest
        self.killphraseSalt = killphraseSalt
        self.killphraseDigest = killphraseDigest
        self.tintColor = tintColor
        self.lockState = lockState
        self.item = item
    }
}

public struct VaultBackupRGBColor: Codable, Equatable {
    public var red, green, blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

extension VaultBackupItem {
    /// A individual vault item with enough information to reconstruct it.
    public enum Item: Codable, Equatable {
        case otp(data: OTP)
        case note(data: Note)
        case encrypted(data: Encrypted)
    }

    public enum SearchableLevel: String, Codable {
        case none = "NONE"
        case full = "FULL"
        case onlyTitle = "ONLY_TITLE"
        case onlyPassphrase = "ONLY_PASSPHRASE"
    }

    public enum Visibility: String, Codable {
        case always = "ALWAYS"
        case onlySearch = "ONLY_SEARCH"
    }

    public enum LockState: String, Codable {
        case notLocked = "NOT_LOCKED"
        case lockedWithNativeSecurity = "LOCKED_NATIVE"
    }

    public enum TextFormat: String, Codable {
        case plain = "PLAIN"
        case markdown = "MARKDOWN"
    }

    /// An encrypted item.
    public struct Encrypted: Codable, Equatable {
        public var version: String
        public var title: String
        public var data: Data
        public var authentication: Data
        public var encryptionIV: Data
        public var keygenSalt: Data
        public var keygenSignature: String

        public init(
            version: String,
            title: String,
            data: Data,
            authentication: Data,
            encryptionIV: Data,
            keygenSalt: Data,
            keygenSignature: String,
        ) {
            self.version = version
            self.title = title
            self.data = data
            self.authentication = authentication
            self.encryptionIV = encryptionIV
            self.keygenSalt = keygenSalt
            self.keygenSignature = keygenSignature
        }

        /// Backups are encoded with snake case keys. `encryptionIV` encodes as `encryption_iv`, but that decodes as
        /// `encryptionIv`, which wouldn't match the property: no backup containing an encrypted item could be
        /// restored. This key encodes the same `encryption_iv` as always, and decodes it too.
        enum CodingKeys: String, CodingKey {
            case version
            case title
            case data
            case authentication
            case encryptionIV = "encryptionIv"
            case keygenSalt
            case keygenSignature
        }
    }

    /// A backed up OTP code.
    public struct OTP: Codable, Equatable {
        public var secretFormat: String
        public var secretData: Data
        public var authType: String
        public var period: UInt64?
        public var counter: UInt64?
        public var algorithm: String
        public var digits: UInt16
        public var accountName: String
        public var issuer: String

        public init(
            secretFormat: String,
            secretData: Data,
            authType: String,
            period: UInt64? = nil,
            counter: UInt64? = nil,
            algorithm: String,
            digits: UInt16,
            accountName: String,
            issuer: String = "",
        ) {
            self.secretFormat = secretFormat
            self.secretData = secretData
            self.authType = authType
            self.period = period
            self.counter = counter
            self.algorithm = algorithm
            self.digits = digits
            self.accountName = accountName
            self.issuer = issuer
        }
    }

    /// A backed up secure note.
    public struct Note: Codable, Equatable {
        public var title: String
        public var rawContents: String?
        public var format: TextFormat

        public init(title: String, rawContents: String?, format: TextFormat) {
            self.title = title
            self.rawContents = rawContents
            self.format = format
        }
    }
}
