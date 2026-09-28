import CryptoKit
import Foundation
import FoundationExtensions
import VaultCore

/// The HMAC keys on this device for one kind of phrase digest, killphrases or search passphrases.
///
/// - **This device's own key** makes every new digest. It's made and stored the first time it's needed.
/// - **Keys from backups** are those restored backups brought with them, which their items' digests were made with
///   on another device, or on this one before an erase. They're only ever matched against: a phrase set again after a
///   restore is digested with this device's own key.
///
/// Both are keychain items with `.whenUnlocked` access (no biometric prompt), never synced, so matching works as soon
/// as the device is unlocked. Every backup carries every key, and every match tries every key
/// (`anyKey(of:authenticates:message:)`). An erase deletes both items (`VaultEraser`).
struct HMACKeyring: Sendable {
    private let secureStorage: any SecureStorage
    private let ownKeyItem: String
    private let backupKeysItem: String

    init(
        secureStorage: any SecureStorage,
        ownKeyItem: VaultIdentifiers.SecureStorageKey,
        backupKeysItem: VaultIdentifiers.SecureStorageKey,
    ) {
        self.secureStorage = secureStorage
        self.ownKeyItem = ownKeyItem.rawValue
        self.backupKeysItem = backupKeysItem.rawValue
    }

    /// This device's own key, made and stored if there isn't one yet.
    func loadOrCreateOwnKey() async throws -> KeyData<32> {
        if let existing = try await secureStorage.retrieveSilent(key: ownKeyItem) {
            return try KeyData<32>(data: existing)
        }
        let fresh = KeyData<32>.random()
        try await secureStorage.storeSilent(data: fresh.data, forKey: ownKeyItem)
        return fresh
    }

    /// The keys restored backups brought, in the order they were added. Never this device's own key.
    func loadKeysFromBackups() async throws -> [KeyData<32>] {
        guard let data = try await secureStorage.retrieveSilent(key: backupKeysItem) else { return [] }
        return Self.keys(in: data)
    }

    /// Adds the keys a restored backup brought. Keys already on the keyring, this device's own included, are skipped,
    /// and nothing's written if every key was.
    func addKeysFromBackup(_ keys: [KeyData<32>]) async throws {
        guard keys.isNotEmpty else { return }
        let ownKey = try await loadOrCreateOwnKey()
        let existing = try await loadKeysFromBackups()
        var keysFromBackups = existing
        for key in keys where key != ownKey && !keysFromBackups.contains(key) {
            keysFromBackups.append(key)
        }
        guard keysFromBackups.count > existing.count else { return }
        let data = keysFromBackups.reduce(into: Data()) { $0.append($1.data) }
        try await secureStorage.storeSilent(data: data, forKey: backupKeysItem)
    }

    /// The keys stored one after another. Bytes left over that don't make a whole key are ignored.
    private static func keys(in data: Data) -> [KeyData<32>] {
        let length = KeyData<32>.length
        return stride(from: data.startIndex, to: data.endIndex - length + 1, by: length).compactMap { start in
            try? KeyData<32>(data: Data(data[start ..< start + length]))
        }
    }
}

// MARK: - Matching

extension HMACKeyring {
    /// Whether `code` is the HMAC-SHA256 of `message` under any of `keys`.
    ///
    /// Every key is tried, with CryptoKit's `isValidAuthenticationCode`, which compares in constant time, and none is
    /// skipped once one has matched. So the time a match takes depends only on how many keys there are, not on which
    /// key matched, or whether any did.
    static func anyKey(of keys: [SymmetricKey], authenticates code: Data, message: Data) -> Bool {
        var matched = false
        for key in keys {
            let isValid = HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: message, using: key)
            matched = isValid || matched
        }
        return matched
    }
}
