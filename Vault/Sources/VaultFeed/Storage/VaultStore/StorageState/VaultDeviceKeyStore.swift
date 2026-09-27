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

    /// The key's bytes, as the keychain returns them, are copied straight into the key and then zeroed.
    public func deviceKey() throws -> SymmetricKey? {
        var query = Self.itemQuery(accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let result, CFGetTypeID(result) == CFDataGetTypeID() else {
                throw SwiftSecurityError.invalidParameter
            }
            return try Self.takeKey(from: unsafeDowncast(result, to: CFData.self))
        case errSecItemNotFound:
            return nil
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// The copy of the key's bytes made for the keychain is zeroed once it's stored, as far as it can be: the
    /// keychain keeps its own.
    public func makeNewDeviceKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        var keyData = key.withUnsafeBytes { Data($0) }
        defer { SlotRandom.wipe(&keyData) }
        try save(keyData)
        return key
    }

    /// Stores the key's bytes in the item. The queries holding them go when it returns, so they can be zeroed.
    private func save(_ keyData: Data) throws {
        let itemQuery = Self.itemQuery(accessGroup: accessGroup)
        let attributes = Self.attributes(for: keyData)
        switch SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let status = SecItemAdd(itemQuery.merging(attributes) { $1 } as CFDictionary, nil)
            guard status == errSecSuccess else { throw SwiftSecurityError(rawValue: status) }
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// Makes the key from the keychain's result, then zeroes the result's bytes. Nothing else holds the result: it
    /// came from a copy call.
    private static func takeKey(from data: CFData) throws -> SymmetricKey {
        let length = CFDataGetLength(data)
        guard let bytes = CFDataGetBytePtr(data) else { throw SwiftSecurityError.invalidParameter }
        defer { _ = memset_s(UnsafeMutableRawPointer(mutating: bytes), length, 0, length) }
        guard length == 32 else { throw SwiftSecurityError.invalidParameter }
        return SymmetricKey(data: UnsafeRawBufferPointer(start: bytes, count: length))
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
            kSecAttrService as String: VaultIdentifiers.SecureStorageKey.vaultDeviceKey.rawValue,
            kSecAttrSynchronizable as String: false,
            // Makes macOS use the same keychain as iOS.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// What's stored in the item: the key's bytes, readable once the device has been unlocked after starting up.
    static func attributes(for keyData: Data) -> [String: Any] {
        [
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }
}
