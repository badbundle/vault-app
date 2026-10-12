import Foundation
import Security
import SwiftSecurity
import VaultCore

/// One of the keychain items the app and its AutoFill extension share: a password item under its key's service, that
/// never syncs.
///
/// It's kept in the keychain access group only they have (`VaultSharedStorage.keychainGroupID`). Versions before
/// VAULT-129 kept it in the App Group's, which the iOS widget extension has too, so until `moveFromTheAppGroup()` has
/// moved it, it's read from there:
///
/// - **Reading** looks in the shared group, then in the App Group's, then in the shared group again: a move adds the
///   item to the shared group before it deletes it from the App Group's, so one that finished in between left it
///   there. A group that can't be read throws, rather than reading as empty.
/// - **Writing** only ever writes the shared group. Whatever writes it has read the item first, so once the shared
///   group holds the item, that's its current value, and the App Group's is older or the same.
/// - **Removing** deletes the App Group's first, then the shared group's, so a delete that fails never leaves reads
///   finding an older value than before.
struct SharedKeychainItem: Sendable {
    let key: VaultIdentifiers.SecureStorageKey
    /// Where it's kept: the shared group, or none, for tests that only check the queries.
    let accessGroup: String?
    /// Where earlier versions kept it, the App Group's, or `nil` if there's nowhere it moves from.
    let formerAccessGroup: String?
    private let keychain: any KeychainCalls

    init(
        key: VaultIdentifiers.SecureStorageKey,
        accessGroup: String? = VaultSharedStorage.keychainGroupID,
        formerAccessGroup: String? = VaultSharedStorage.appGroupID,
        keychain: any KeychainCalls = SystemKeychainCalls(),
    ) {
        self.key = key
        self.accessGroup = accessGroup
        self.formerAccessGroup = formerAccessGroup == accessGroup ? nil : formerAccessGroup
        self.keychain = keychain
    }

    /// The item's bytes, or `nil` if neither group holds it.
    ///
    /// - Throws: If a group can't be read.
    func data() throws -> Data? {
        if let data = try readData(in: accessGroup) {
            return data
        }
        guard let formerAccessGroup else { return nil }
        if let data = try readData(in: formerAccessGroup) {
            return data
        }
        return try readData(in: accessGroup)
    }

    /// Stores the item, with `attributes`, in the shared group: in place, if it's there, so there's never a moment
    /// without it.
    func save(_ attributes: [String: Any]) throws {
        let query = query(in: accessGroup)
        switch keychain.update(query, with: attributes) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let status = keychain.add(query.merging(attributes) { $1 })
            guard status == errSecSuccess else { throw SwiftSecurityError(rawValue: status) }
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// Stores the item, with `attributes`, in the shared group if it isn't there yet. `false`, changing nothing, if it
    /// is.
    func add(_ attributes: [String: Any]) throws -> Bool {
        switch keychain.add(query(in: accessGroup).merging(attributes) { $1 }) {
        case errSecSuccess:
            true
        case errSecDuplicateItem:
            false
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// Deletes the item from both groups. Does nothing where there's none.
    func remove() throws {
        if let formerAccessGroup {
            try delete(in: formerAccessGroup)
        }
        try delete(in: accessGroup)
    }

    /// Whether the App Group's access group still holds the item.
    func isInTheAppGroup() throws -> Bool {
        guard let formerAccessGroup else { return false }
        switch keychain.copyMatching(query(in: formerAccessGroup)).status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// Moves the item from the App Group's access group to the shared one, if it's still there. It can be called any
    /// number of times, and by the app and the AutoFill extension at once.
    ///
    /// 1. Reads the item there, with its accessibility.
    /// 2. Adds a copy to the shared group, with the same bytes and accessibility, never synced, unless the shared group
    ///    holds the item already. If it does, that's kept as it is: it's the item's current value, written since, or
    ///    another process has just moved it.
    /// 3. Reads the shared group's back: it has to be there, with the same accessibility, never synced, and if this
    ///    added it, the same bytes.
    /// 4. Only then deletes the item from the App Group's.
    ///
    /// - Throws: If a step fails, leaving the item in the App Group's group, where reads still find it, for the next
    ///   call to move. A copy that doesn't read back as the item throws `MoveError.copyDoesNotMatch`.
    func moveFromTheAppGroup() throws {
        guard let formerAccessGroup, let original = try read(in: formerAccessGroup) else { return }
        var copy = query(in: accessGroup)
        copy[kSecValueData as String] = original.data
        copy[kSecAttrAccessible as String] = original.accessible
        let added: Bool
        switch keychain.add(copy) {
        case errSecSuccess:
            added = true
        case errSecDuplicateItem:
            added = false
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
        guard let moved = try read(in: accessGroup),
              moved.accessible == original.accessible,
              !moved.synchronizable,
              !added || moved.data == original.data
        else {
            throw MoveError.copyDoesNotMatch
        }
        try delete(in: formerAccessGroup)
    }

    /// Why a move stopped before deleting the item from the App Group's access group.
    enum MoveError: Error, Equatable {
        /// The shared group's copy didn't read back as the item it was copied from.
        case copyDoesNotMatch
    }

    /// Identifies the item in `accessGroup`: a password item under the key's service, that doesn't sync.
    func query(in accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.keychainService,
            kSecAttrSynchronizable as String: false,
            // Makes macOS use the same keychain as iOS.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// The item's bytes in `accessGroup`, or `nil` if it doesn't hold it.
    private func readData(in accessGroup: String?) throws -> Data? {
        var query = query(in: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = keychain.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw SwiftSecurityError.invalidParameter }
            return data
        case errSecItemNotFound:
            return nil
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// The item as `accessGroup` holds it, with its attributes, or `nil` if it doesn't hold it.
    private func read(in accessGroup: String?) throws -> StoredItem? {
        var query = query(in: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = keychain.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let attributes = result as? [String: Any],
                  let data = attributes[kSecValueData as String] as? Data,
                  let accessible = attributes[kSecAttrAccessible as String] as? String
            else {
                throw SwiftSecurityError.invalidParameter
            }
            let synchronizable = attributes[kSecAttrSynchronizable as String] as? Bool ?? false
            return StoredItem(data: data, accessible: accessible, synchronizable: synchronizable)
        case errSecItemNotFound:
            return nil
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    private func delete(in accessGroup: String?) throws {
        let status = keychain.delete(query(in: accessGroup))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwiftSecurityError(rawValue: status)
        }
    }

    private struct StoredItem {
        var data: Data
        var accessible: String
        var synchronizable: Bool
    }
}

/// The keychain calls `SharedKeychainItem` makes, so tests can stand in for the keychain, which hostless tests can't
/// reach.
protocol KeychainCalls: Sendable {
    /// `SecItemCopyMatching`.
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: AnyObject?)
    /// `SecItemAdd`, returning nothing.
    func add(_ item: [String: Any]) -> OSStatus
    /// `SecItemUpdate`.
    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus
    /// `SecItemDelete`.
    func delete(_ query: [String: Any]) -> OSStatus
}

/// The keychain itself.
struct SystemKeychainCalls: KeychainCalls {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: AnyObject?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func add(_ item: [String: Any]) -> OSStatus {
        SecItemAdd(item as CFDictionary, nil)
    }

    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Moves the keychain items the app and its AutoFill extension share out of the App Group's access group, where
/// versions before VAULT-129 kept them, into the shared one (`VaultSharedStorage.keychainGroupID`): the count of
/// attempts at the App Lock Password, the wrap stamp, and the Mac's app lock settings. The device key stays in the App
/// Group's, as the iOS widget extension reads it (`VaultDeviceKeychainStore`).
public enum SharedKeychainItems {
    /// Moves every item still in the App Group's group, once in each process: the first call starts it, and every
    /// call waits for it to finish. An item that can't be moved stays where it is, and is read from there, until a
    /// later launch moves it.
    ///
    /// The app calls it as it launches, before anything that could erase, and the AutoFill extension as it starts.
    public static func moveFromTheAppGroup() async {
        await move.value
    }

    private static let move = Task {
        try? await AppLockPasswordAttemptKeychainStorage().moveFromTheAppGroup()
        try? VaultWrapStampKeychainStorage().moveFromTheAppGroup()
        try? AppLockDeviceSettingsKeychainStorage().moveFromTheAppGroup()
    }
}
