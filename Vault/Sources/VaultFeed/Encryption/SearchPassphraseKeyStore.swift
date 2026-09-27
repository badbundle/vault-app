import Foundation
import FoundationExtensions
import VaultCore

/// Loads (or generates and stores) the 256-bit HMAC key used by
/// `SearchPassphraseDigester`.
///
/// The key is held in the device keychain with `.whenUnlocked` access (no
/// biometric prompt) so the search-passphrase match path works as soon as
/// the device is unlocked, mirroring the killphrase key.
///
/// `loadOrCreate` is idempotent: on first call after install/upgrade, it
/// generates a random key and stores it; on every subsequent call it
/// returns the stored value.
///
/// @mockable(typealias: Key = KeyData<32>)
public protocol SearchPassphraseKeyStore<Key>: Sendable {
    associatedtype Key: Sendable
    func loadOrCreate() async throws -> Key
}

public struct SearchPassphraseKeyStoreImpl: SearchPassphraseKeyStore {
    private let secureStorage: any SecureStorage

    public init(secureStorage: any SecureStorage) {
        self.secureStorage = secureStorage
    }

    public func loadOrCreate() async throws -> KeyData<32> {
        if let existing = try await secureStorage.retrieveSilent(key: KeychainKey.searchPassphraseKey) {
            return try KeyData<32>(data: existing)
        }
        let fresh = KeyData<32>.random()
        try await secureStorage.storeSilent(data: fresh.data, forKey: KeychainKey.searchPassphraseKey)
        return fresh
    }

    private enum KeychainKey {
        static let searchPassphraseKey = VaultIdentifiers.SecureStorageKey.searchPassphraseKey.rawValue
    }
}
