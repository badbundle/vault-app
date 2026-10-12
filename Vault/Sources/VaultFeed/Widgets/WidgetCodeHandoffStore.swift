import Foundation
import Security
import SwiftSecurity
import VaultCore

/// Keeps the codes the Mac app hands its widgets (`WidgetCodeHandoff`) where the widget extension can read them: a
/// keychain item in the widgets' keychain access group (`WidgetKeychainItem.codes`), which only the app and the widget
/// extension have.
///
/// The widget extension has no App Group, so this is all it shares with the app: an App Group is also a keychain
/// access group for every target that has it, and would let the extension read the App Group's keychain items.
///
/// The app publishes and withdraws (`VaultMacWidgetCodes`). The widget extension only reads (`current(at:)`).
public struct WidgetCodeHandoffStore: Sendable {
    private let keychain: any WidgetKeychainStoring

    public init(keychain: any WidgetKeychainStoring = WidgetKeychainItem.codes) {
        self.keychain = keychain
    }

    /// Hands `handoff` to the widgets, in place of any before it.
    public func publish(_ handoff: WidgetCodeHandoff) throws {
        try keychain.save(JSONEncoder().encode(handoff))
    }

    /// Takes the codes back from the widgets: deletes them, or if that fails, puts a handoff with no codes, which has
    /// already expired, in their place.
    ///
    /// - Throws: If neither can be done, as can happen while the Mac is locked. The codes it holds then run out by
    ///   themselves, within `WidgetCodeHandoff.window`, and the widget extension can't read them while the Mac stays
    ///   locked.
    public func withdraw() throws {
        do {
            try keychain.remove()
        } catch {
            try keychain.save(JSONEncoder().encode(WidgetCodeHandoff.withdrawn))
        }
    }

    /// Deletes the codes, as an erase does, which tries again if it can't.
    public func remove() throws {
        try keychain.remove()
    }

    /// The handoff the widgets may show at `now`, or `nil` while there's none: the app hasn't handed one over since it
    /// last withdrew one, it's expired, or the Mac's locked, so the keychain can't be read.
    public func current(at now: Date) -> WidgetCodeHandoff? {
        guard let data = try? keychain.read(),
              let handoff = try? JSONDecoder().decode(WidgetCodeHandoff.self, from: data),
              now < handoff.expiresAt
        else {
            return nil
        }
        return handoff
    }
}

extension WidgetCodeHandoff {
    /// What's left in place of codes that couldn't be deleted: none, and already expired.
    static var withdrawn: WidgetCodeHandoff {
        WidgetCodeHandoff(id: UUID(), expiresAt: .distantPast, items: [])
    }
}

/// Where one of the widgets' keychain items is kept.
public protocol WidgetKeychainStoring: Sendable {
    /// The bytes, or `nil` if there are none.
    func read() throws -> Data?
    /// Stores `data` in place of whatever was there.
    func save(_ data: Data) throws
    /// Deletes the bytes. Does nothing if there are none.
    func remove() throws
}

/// One of the items the Mac app shares with its widget extension in the keychain:
///
/// - **In the widgets' own keychain access group**, `…vault.widgets`, which only the app and the widget extension
///   have. The widget extension has no other, and no App Group, so it can't read the App Group's items, such as the
///   device key, nor those the app shares with the AutoFill extension, such as the attempt counter, and the AutoFill
///   extension can't read these.
/// - **Kept on this Mac only**: never synced, and never restored to another Mac.
///
/// On iOS there's no such group, and nothing is ever stored: the iOS widgets read the vault themselves while the App
/// Lock Password is off (`WidgetVaultLoader`), and show it locked while it's on (G44). Deleting finds nothing.
public struct WidgetKeychainItem: WidgetKeychainStoring {
    #if os(macOS)
    /// The widgets' keychain access group (docs/mac-app.md, "Keychain").
    public static let accessGroup: String? = "442P244AFS.com.badbundle.vault.widgets"
    #else
    public static let accessGroup: String? = nil
    #endif

    /// The codes the app hands its widgets, readable only while the Mac is unlocked
    /// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
    public static var codes: WidgetKeychainItem {
        WidgetKeychainItem(
            accessGroup: accessGroup,
            service: VaultIdentifiers.SecureStorageKey.widgetCodes.keychainService,
            accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
        )
    }

    /// The note of a code a widget copied, which holds nothing of the code, readable once the Mac has been unlocked
    /// after starting up (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), so the app can read it as the Mac locks.
    public static var copiedCode: WidgetKeychainItem {
        WidgetKeychainItem(
            accessGroup: accessGroup,
            service: VaultIdentifiers.SecureStorageKey.widgetCopiedCode.keychainService,
            accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
        )
    }

    let accessGroup: String?
    let service: String
    let accessibility: String

    /// - Parameter service: What the item is kept under: tests keep theirs apart from the app's.
    public init(accessGroup: String?, service: String, accessibility: String) {
        self.accessGroup = accessGroup
        self.service = service
        self.accessibility = accessibility
    }

    public func read() throws -> Data? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { throw SwiftSecurityError.invalidParameter }
            return data
        case errSecItemNotFound:
            return nil
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    public func save(_ data: Data) throws {
        let attributes = attributes(for: data)
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

    public func remove() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwiftSecurityError(rawValue: status)
        }
    }

    /// Identifies the item: a password item under `service`, in `accessGroup`, that doesn't sync.
    var itemQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            // Makes macOS use the same keychain as iOS.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// What's stored in the item: `data`, readable when `accessibility` says, and only on this Mac.
    func attributes(for data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
        ]
    }
}
