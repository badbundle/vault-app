import Foundation
import FoundationExtensions
import VaultCore

/// Loads (or generates and stores) the 256-bit HMAC key used by
/// `KillphraseDigester`.
///
/// The key is held in the device keychain with `.whenUnlocked` access (no
/// biometric prompt) so the silent-delete-on-search UX continues to work
/// the moment the device is unlocked, without depending on whether the
/// user has opened the backup-password flow.
///
/// `loadOrCreate` is idempotent: on first call after install/upgrade, it
/// generates a random key and stores it; on every subsequent call it
/// returns the stored value.
///
/// @mockable(typealias: Key = KeyData<32>)
public protocol KillphraseKeyStore<Key>: Sendable {
    associatedtype Key: Sendable
    func loadOrCreate() async throws -> Key
}

public struct KillphraseKeyStoreImpl: KillphraseKeyStore {
    private let secureStorage: any SecureStorage

    public init(secureStorage: any SecureStorage) {
        self.secureStorage = secureStorage
    }

    public func loadOrCreate() async throws -> KeyData<32> {
        if let existing = try await secureStorage.retrieveSilent(key: KeychainKey.killphraseKey) {
            return try KeyData<32>(data: existing)
        }
        let fresh = KeyData<32>.random()
        try await secureStorage.storeSilent(data: fresh.data, forKey: KeychainKey.killphraseKey)
        return fresh
    }

    private enum KeychainKey {
        static let killphraseKey = VaultIdentifiers.SecureStorageKey.killphraseKey.rawValue
    }
}
