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
/// counted at once in the same process can't both see the same count. `withExclusiveAccess(_:)` does the same across
/// processes, for the app and the AutoFill extension running side by side, as they can on an iPad.
protocol AppLockPasswordAttemptStorage: Sendable {
    /// The record, or `nil` if there isn't one: no attempts since the password was last entered correctly.
    func load() throws -> AppLockPasswordAttemptRecord?
    /// Replaces the record. It's in storage by the time this returns.
    func save(_ record: AppLockPasswordAttemptRecord) throws
    /// Removes the record. Does nothing if there isn't one.
    func remove() throws
    /// Runs `body`, which reads and writes the record, while no other process can.
    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T
}

extension AppLockPasswordAttemptStorage {
    /// Storage no other process shares needs no more than the counter's own isolation.
    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        try body()
    }
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
    /// The file whose lock the app and its extensions take around each change to the record.
    private let lockFileURL: @Sendable () -> URL

    init(
        accessGroup: String? = VaultSharedStorage.appGroupID,
        lockFileURL: @escaping @Sendable () -> URL = {
            VaultSharedStorage.directory().appending(path: "app-lock-password-attempts.lock")
        },
    ) {
        self.accessGroup = accessGroup
        self.lockFileURL = lockFileURL
    }

    /// Holds an exclusive `flock` on the lock file for `body`, waiting for another process to let go of it first.
    /// Every process takes it only for the moment it reads and writes the keychain item.
    func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        let descriptor = open(lockFileURL().path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return try body()
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
            kSecAttrService as String: VaultIdentifiers.SecureStorageKey.appLockPasswordAttempts.rawValue,
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
