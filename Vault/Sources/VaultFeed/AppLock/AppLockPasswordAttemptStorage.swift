import Foundation
import Security
import SwiftSecurity

/// What `AppLockPasswordAttemptCounter` keeps between launches.
struct AppLockPasswordAttemptRecord: Codable, Equatable {
    /// Attempts at the password since it was last entered correctly. An attempt still underway counts, and so does
    /// one the app was stopped in the middle of.
    var count: Int
    /// When the latest of them was counted, by the app lock's clock. The delay before the next one runs from here.
    var latestAt: ContinuousClock.Instant
}

/// Where `AppLockPasswordAttemptCounter` keeps its record.
///
/// Synchronous, so that the counter reads, updates and writes the record without pausing in between: two attempts
/// counted at once in the same process can't both see the same count.
protocol AppLockPasswordAttemptStorage: Sendable {
    /// The record, or `nil` if there isn't one: no attempts since the password was last entered correctly.
    func load() throws -> AppLockPasswordAttemptRecord?
    /// Replaces the record. It's in storage by the time this returns.
    func save(_ record: AppLockPasswordAttemptRecord) throws
    /// Removes the record. Does nothing if there isn't one.
    func remove() throws
}

/// Keeps the password attempt record in the keychain, on this device only.
///
/// The keychain outlives the app: relaunching it, or installing a new version over the top, keeps the count. The item
/// is readable only while the device is unlocked, never syncs to iCloud Keychain, and never moves to another device
/// with a backup. It's in the App Group's access group, so the AutoFill extension can count attempts made there
/// against the same record.
///
/// This talks to the keychain directly, rather than through `SecureStorage`, so that it can update the item in
/// place. `SecureStorage` removes an item and then adds it again, and an app stopped in between would forget every
/// wrong attempt.
struct AppLockPasswordAttemptKeychainStorage: AppLockPasswordAttemptStorage {
    let accessGroup: String?

    init(accessGroup: String? = VaultSharedStorage.appGroupID) {
        self.accessGroup = accessGroup
    }

    func load() throws -> AppLockPasswordAttemptRecord? {
        var query = Self.itemQuery(accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { throw SwiftSecurityError.invalidParameter }
            return try JSONDecoder().decode(AppLockPasswordAttemptRecord.self, from: data)
        case errSecItemNotFound:
            return nil
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    func save(_ record: AppLockPasswordAttemptRecord) throws {
        let query = Self.itemQuery(accessGroup: accessGroup)
        let attributes = try Self.attributes(for: record)
        switch SecItemUpdate(query as CFDictionary, attributes as CFDictionary) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard status == errSecSuccess else { throw SwiftSecurityError(rawValue: status) }
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    func remove() throws {
        let status = SecItemDelete(Self.itemQuery(accessGroup: accessGroup) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// Identifies the item: a password item for the attempt record, in `accessGroup`, that doesn't sync.
    static func itemQuery(accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VaultIdentifiers.SecureStorageKey.appLockPasswordAttempts,
            kSecAttrSynchronizable as String: false,
            // Makes macOS use the same keychain as iOS.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// What's stored in the item: the record, readable only while the device is unlocked, on this device only.
    static func attributes(for record: AppLockPasswordAttemptRecord) throws -> [String: Any] {
        try [
            kSecValueData as String: JSONEncoder().encode(record),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }
}
