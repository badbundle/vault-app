import Foundation
import FoundationExtensions

/// One vault's killphrase and search passphrase keyrings: the HMAC keys its phrases' digests are checked with.
///
/// Where they're kept depends on how the vault is stored (`OpenVaultPhraseKeyrings`):
///
/// - **An encrypted vault the App Lock Password opens** keeps its own in its payload (`VaultMetadata.keyrings`), so
///   they move with the vault file, and a duress vault never holds another vault's own keys.
/// - **The plain store**, which isn't encrypted, keeps them in the keychain (`HMACKeyring`), never beside the digests.
/// - **A vault the device key opens**, while the password is off, keeps them in the keychain too
///   (`DevicePhraseKeyrings`): its file opens with a key in the keychain, so keys in it would be beside the digests.
///
/// Each kind is a `Keyring`: the key every new digest is made with, and the keys that are only matched against.
public struct VaultPhraseKeyrings: Equatable, Sendable {
    public var killphrase: Keyring
    public var searchPassphrase: Keyring

    public init(killphrase: Keyring, searchPassphrase: Keyring) {
        self.killphrase = killphrase
        self.searchPassphrase = searchPassphrase
    }

    /// New keyrings, with a random key of their own for each kind and no others: a new vault's.
    public static func random() -> VaultPhraseKeyrings {
        VaultPhraseKeyrings(killphrase: .random(), searchPassphrase: .random())
    }

    /// The kinds of phrase a keyring checks.
    public enum Kind: CaseIterable, Sendable {
        case killphrase
        case searchPassphrase
    }

    public subscript(kind: Kind) -> Keyring {
        get {
            switch kind {
            case .killphrase: killphrase
            case .searchPassphrase: searchPassphrase
            }
        }
        set {
            switch kind {
            case .killphrase: killphrase = newValue
            case .searchPassphrase: searchPassphrase = newValue
            }
        }
    }
}

// MARK: - Keyring

extension VaultPhraseKeyrings {
    /// The keys for one kind of phrase.
    public struct Keyring: Equatable, Sendable {
        /// The key every new digest is made with. It's only ever this vault's: made for it, or moved to it.
        public var ownKey: KeyData<32>
        /// Keys that are only matched against, never used for a new digest: those restored backups brought, and those
        /// the vault's phrases were digested with before it had keys of its own. Never `ownKey`, and never one twice.
        public var keysFromBackups: [KeyData<32>]

        public init(ownKey: KeyData<32>, keysFromBackups: [KeyData<32>] = []) {
            self.ownKey = ownKey
            self.keysFromBackups = []
            add(keysFromBackups)
        }

        /// A keyring with a new random key of its own, and no others.
        public static func random() -> Keyring {
            Keyring(ownKey: .random())
        }

        /// Every key: the vault's own first, then the others in the order they were added. A backup carries them all.
        public var allKeys: [KeyData<32>] {
            [ownKey] + keysFromBackups
        }

        /// Adds keys to match against, skipping the vault's own key and any already here.
        ///
        /// - Returns: Whether any key was added.
        @discardableResult
        public mutating func add(_ keys: [KeyData<32>]) -> Bool {
            let before = keysFromBackups.count
            for key in keys where key != ownKey && !keysFromBackups.contains(key) {
                keysFromBackups.append(key)
            }
            return keysFromBackups.count > before
        }
    }
}

// MARK: - Adding keyrings

extension VaultPhraseKeyrings {
    /// These keyrings, with every key of `other`'s added to match against: their own keys stay their own.
    func adding(_ other: VaultPhraseKeyrings) -> VaultPhraseKeyrings {
        var keyrings = self
        for kind in Kind.allCases {
            keyrings[kind].add(other[kind].allKeys)
        }
        return keyrings
    }
}

// MARK: - Taking a copy

extension VaultPhraseKeyrings {
    /// Keyrings for a vault that takes a copy of keys it shares with other vaults, as an encrypted vault made before
    /// vaults kept their own does from the keychain: a new key of its own for each kind, and every key it was given
    /// to match against. A key it was given never makes a digest in it, so from then on no two vaults make digests
    /// with the same key.
    ///
    /// - Parameters:
    ///   - killphraseKeys: The keys its killphrases may have been digested with.
    ///   - searchPassphraseKeys: The keys its search passphrases may have been digested with.
    static func takingCopies(
        killphraseKeys: [KeyData<32>],
        searchPassphraseKeys: [KeyData<32>],
    ) -> VaultPhraseKeyrings {
        VaultPhraseKeyrings(
            killphrase: Keyring(ownKey: .random(), keysFromBackups: killphraseKeys),
            searchPassphrase: Keyring(ownKey: .random(), keysFromBackups: searchPassphraseKeys),
        )
    }
}

// MARK: - Codable

extension VaultPhraseKeyrings: Codable {
    private enum CodingKeys: String, CodingKey {
        case killphrase, searchPassphrase
    }
}

extension VaultPhraseKeyrings.Keyring: Codable {
    private enum CodingKeys: String, CodingKey {
        case ownKey, keysFromBackups
    }

    /// Every key is always written, so every keyring has the same shape.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ownKey, forKey: .ownKey)
        try container.encode(keysFromBackups, forKey: .keysFromBackups)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ownKey: container.decode(KeyData<32>.self, forKey: .ownKey),
            keysFromBackups: container.decodeIfPresent([KeyData<32>].self, forKey: .keysFromBackups) ?? [],
        )
    }
}
