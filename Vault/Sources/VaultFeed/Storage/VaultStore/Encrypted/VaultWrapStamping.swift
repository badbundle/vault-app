import Foundation
import FoundationExtensions
import Security
import SwiftSecurity

/// Chooses the wrap time a wrap records in a slot's key box (`VaultSlotFile.OpenedSlot.wrappedAt`).
///
/// When one password opens more than one slot, the most recently wrapped wins. A wrap time read from a clock the user
/// can set back would let whoever holds the device choose which slot wins, and so test whether a password opens
/// another vault without counting an attempt. Say someone inside a duress vault sets the clock back, makes a duress
/// vault with a guess at another vault's password, locks, and unlocks with the guess: the new vault would be older
/// than every other, so a right guess would open the vault it matched, and a wrong one the new, empty vault. Every
/// unlock would succeed and reset the attempt counter, so they could guess without delay or erase. Every wrap takes
/// its time from here: creating the first vault (`VaultEncryptionConverter`), making a duress vault
/// (`EncryptedVaultStore.makeDuressVault(password:)`) and rewrapping.
///
/// `VaultDeviceWrapStamper` is the implementation: each wrap later than the last one this device made, and than the
/// slot's own.
public protocol VaultWrapStamping: Sendable {
    /// The wrap time for a slot being rewrapped, which was last wrapped at `previous`. It's after `previous`.
    ///
    /// For a vault made from another, `previous` is that vault's wrap time; for the first vault in a new file, it's
    /// `.distantPast`.
    func nextWrapStamp(rewrapping previous: Date) throws -> Date
}

/// Stamps wraps with times that only ever go forward on this device, whatever its clock says:
/// `max(now, the last stamp + 1 ms, previous + 1 ms)`.
///
/// The stamp is saved before it's returned, in a keychain item on this device only (`VaultWrapStampKeychainStorage`),
/// so every later stamp is later still, across launches. If it can't be saved, it throws and nothing is wrapped,
/// because a later wrap could get the same time. Every vault that opens raises it to its own wrap time
/// (`noteWrap(at:)`), so after a restore onto a new device, where the stamp isn't restored, wraps made once the user
/// has opened a vault there still follow that vault's.
///
/// What's left: on a device whose stamp is gone, a duress vault made before the user has opened the real vault there
/// is stamped only after the clock and the duress vault it's made from, so a clock set back can still make it older
/// than the real vault.
///
/// Stamps are milliseconds since 1970, as the slot file stores them. Never log, print or measure them.
public final class VaultDeviceWrapStamper: VaultWrapStamping {
    private let storage: any VaultWrapStampStorage
    private let currentDate: @Sendable () -> Date
    /// Reading, raising and saving the stamp happen together, so two wraps can't read the same stamp.
    private let lock = SharedMutex(())

    /// A stamper that keeps its stamp in the keychain, on this device only.
    public convenience init() {
        self.init(storage: VaultWrapStampKeychainStorage(), currentDate: { Date() })
    }

    init(storage: any VaultWrapStampStorage, currentDate: @escaping @Sendable () -> Date) {
        self.storage = storage
        self.currentDate = currentDate
    }

    public func nextWrapStamp(rewrapping previous: Date) throws -> Date {
        try lock.modify { _ in
            var earlier = Self.milliseconds(since1970: previous)
            if let saved = try storage.load() {
                earlier = max(earlier, saved)
            }
            let stamp = max(Self.milliseconds(since1970: currentDate()), earlier + 1)
            try storage.save(stamp)
            return Date(timeIntervalSince1970: TimeInterval(stamp) / 1000)
        }
    }

    /// Raises the stamp to at least `date`, for a vault that's just opened, so wraps made from now on follow its.
    ///
    /// - Throws: If the stamp couldn't be read or saved.
    public func noteWrap(at date: Date) throws {
        try lock.modify { _ in
            let wrappedAt = Self.milliseconds(since1970: date)
            if let stamp = try storage.load(), stamp >= wrappedAt {
                return
            }
            try storage.save(wrappedAt)
        }
    }

    private static func milliseconds(since1970 date: Date) -> UInt64 {
        UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
    }
}

/// Where `VaultDeviceWrapStamper` keeps its stamp.
protocol VaultWrapStampStorage: Sendable {
    /// The stamp, in milliseconds since 1970, or `nil` if there isn't one.
    func load() throws -> UInt64?
    /// Replaces the stamp. It's in storage by the time this returns.
    func save(_ stamp: UInt64) throws
}

/// Keeps the wrap stamp in the keychain, on this device only, in the App Group's access group.
///
/// It survives relaunches and updates. It never syncs to iCloud Keychain and never moves to another device with a
/// backup, so a stamp from another time can't be put back with an old backup.
struct VaultWrapStampKeychainStorage: VaultWrapStampStorage {
    let accessGroup: String?

    init(accessGroup: String? = VaultSharedStorage.appGroupID) {
        self.accessGroup = accessGroup
    }

    func load() throws -> UInt64? {
        var query = Self.itemQuery(accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { throw SwiftSecurityError.invalidParameter }
            return try JSONDecoder().decode(UInt64.self, from: data)
        case errSecItemNotFound:
            return nil
        case let status:
            throw SwiftSecurityError(rawValue: status)
        }
    }

    func save(_ stamp: UInt64) throws {
        let query = Self.itemQuery(accessGroup: accessGroup)
        let attributes: [String: Any] = try [
            kSecValueData as String: JSONEncoder().encode(stamp),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
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

    /// Identifies the item: a password item for the stamp, in `accessGroup`, that doesn't sync.
    static func itemQuery(accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VaultIdentifiers.SecureStorageKey.vaultWrapStamp,
            kSecAttrSynchronizable as String: false,
            // Makes macOS use the same keychain as iOS.
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
