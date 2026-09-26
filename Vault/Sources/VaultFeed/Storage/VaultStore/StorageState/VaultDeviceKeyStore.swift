import CryptoKit
import Foundation
import Security
import SwiftSecurity
import VaultCore

/// Keeps the device key `D`, which wraps the open vault's key while the App Lock Password is off (the `deviceKey`
/// storage mode).
///
/// Synchronous, so launch recovery can read it before any store opens.
public protocol VaultDeviceKeyStoring: Sendable {
    /// The device key, or `nil` if there isn't one.
    func deviceKey() throws -> SymmetricKey?
    /// Makes a new, random 256-bit device key in place of any there was, and returns it.
    func makeNewDeviceKey() throws -> SymmetricKey
    /// Deletes the device key. Does nothing if there isn't one.
    func removeDeviceKey() throws
}

/// Keeps the device key in the keychain.
///
/// - **Readable once the device has been unlocked after starting up** (`kSecAttrAccessibleAfterFirstUnlock`), as
///   the plain store's files are (complete protection until the first unlock). With the password off, the widgets
///   show codes as they do today, and they refresh in the background while the device is locked (VAULT-50). A
///   stricter class would break that; a looser one would add nothing they need.
/// - **Restored with a backup**, not `ThisDeviceOnly`, like the encrypted file itself: restoring a backup onto a new
///   iPhone keeps a vault whose password is off openable. It never syncs to iCloud Keychain.
/// - **In the App Group's access group**, like the attempt counter, so the extensions can read it once they're given
///   access (VAULT-50).
/// - **Made new every time the password is turned off**, and deleted when it's turned back on, so it only ever opens
///   copies of the file written while the password was off.
public struct VaultDeviceKeychainStore: VaultDeviceKeyStoring {
    let accessGroup: String?

    public init() {
        self.init(accessGroup: VaultSharedStorage.appGroupID)
    }

    init(accessGroup: String?) {
        self.accessGroup = accessGroup
    }

    public func deviceKey() throws -> SymmetricKey? {
        var query = Self.itemQuery(accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { throw SwiftSecurityError.invalidParameter }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    public func makeNewDeviceKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let itemQuery = Self.itemQuery(accessGroup: accessGroup)
        let attributes = Self.attributes(for: key)
        switch SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary) {
        case errSecSuccess:
            return key
        case errSecItemNotFound:
            let status = SecItemAdd(itemQuery.merging(attributes) { $1 } as CFDictionary, nil)
            guard status == errSecSuccess else { throw SwiftSecurityError(rawValue: status) }
            return key
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    public func removeDeviceKey() throws {
        let status = SecItemDelete(Self.itemQuery(accessGroup: accessGroup) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// Identifies the item: a password item for the device key, in `accessGroup`, that doesn't sync.
    static func itemQuery(accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VaultIdentifiers.SecureStorageKey.vaultDeviceKey,
            kSecAttrSynchronizable as String: false,
            // Makes macOS use the same keychain as iOS.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// What's stored in the item: the key, readable once the device has been unlocked after starting up.
    static func attributes(for key: SymmetricKey) -> [String: Any] {
        [
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }
}
