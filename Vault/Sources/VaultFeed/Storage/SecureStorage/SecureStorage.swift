import Foundation
import LocalAuthentication
import SwiftSecurity

/// Stores data securely on the device (most likely the keychain).
///
/// @mockable
public protocol SecureStorage: Sendable {
    /// Locally stores data with a restrictive access policy that requires
    /// user presence (biometric / passcode) at retrieval time.
    /// Overrides existing value if it exists.
    ///
    /// - Throws: Internal error is thrown if we cannot store to the Keychain.
    func store(data: Data, forKey key: String) async throws
    /// Returns `nil` if the data does not exist for this key.
    ///
    /// - Throws: Internal error is thrown if we cannot retrieve from the Keychain.
    func retrieve(key: String) async throws -> Data?

    /// Locally stores data with a less restrictive policy that does **not**
    /// require user presence — only that the device be unlocked. Use this
    /// for material that the app must read silently (e.g. the killphrase
    /// HMAC key, which has to be available without a biometric prompt so
    /// the silent-delete-on-search UX works).
    ///
    /// Overrides existing value if it exists.
    func storeSilent(data: Data, forKey key: String) async throws
    /// Silent retrieval counterpart. Returns `nil` if no data exists.
    func retrieveSilent(key: String) async throws -> Data?

    /// Reads the attributes of the item stored for this key, never its data.
    ///
    /// This never asks the user to authenticate, even for items stored with
    /// `store(data:forKey:)`: if reading the attributes ever needed user
    /// presence, it throws instead of prompting. Returns `nil` if no data
    /// exists for this key.
    func attributes(key: String) async throws -> SecureStorageAttributes?
}

/// Metadata about an item in `SecureStorage`, readable without its data.
public struct SecureStorageAttributes: Equatable, Sendable {
    /// When the item was last stored.
    public var modificationDate: Date?

    public init(modificationDate: Date?) {
        self.modificationDate = modificationDate
    }
}

public actor SecureStorageImpl: SecureStorage {
    private let keychain: Keychain

    public init(keychain: Keychain) {
        self.keychain = keychain
    }

    public func store(data: Data, forKey key: String) throws {
        try keychain.remove(.credential(for: key))
        let accessPolicy = AccessPolicy(.whenUnlocked, options: [.userPresence])
        try keychain.store(data, query: .credential(for: key), accessPolicy: accessPolicy)
    }

    public func retrieve(key: String) throws -> Data? {
        try keychain.retrieve(.credential(for: key))
    }

    public func storeSilent(data: Data, forKey key: String) throws {
        try keychain.remove(.credential(for: key))
        let accessPolicy = AccessPolicy(.whenUnlocked)
        try keychain.store(data, query: .credential(for: key), accessPolicy: accessPolicy)
    }

    public func retrieveSilent(key: String) throws -> Data? {
        try keychain.retrieve(.credential(for: key))
    }

    public func attributes(key: String) throws -> SecureStorageAttributes? {
        guard let info = try keychain.info(for: Self.attributesQuery(key: key)) else { return nil }
        return SecureStorageAttributes(modificationDate: info.modificationDate)
    }

    /// The query `attributes(key:)` runs, which asks for attributes only (never
    /// the data) and disallows interaction outright: if it would need user
    /// presence, it fails with `errSecInteractionNotAllowed` rather than prompting.
    ///
    /// The context goes into the query directly rather than through
    /// `info(for:authenticationContext:)`, which also sets
    /// `kSecUseAuthenticationUISkip`. Skipping would make an item that needs
    /// authentication look missing instead of failing.
    static func attributesQuery(key: String) -> SecItemQuery<GenericPassword> {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = SecItemQuery<GenericPassword>.credential(for: key)
        query[kSecUseAuthenticationContext as String] = context
        return query
    }
}
