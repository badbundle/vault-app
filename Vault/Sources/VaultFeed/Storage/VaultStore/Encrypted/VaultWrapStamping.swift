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
/// because a later wrap could get the same time.
///
/// **It tracks the device's last use, not its last wrap.** The keychain item is readable at rest by forensic tools, and
/// a stamp that only moved when a key was wrapped would tell someone holding one vault's password that a wrap was
/// made after it: a duress vault made, or another vault's password changed. So every vault that opens moves it too
/// (`noteUse(ofVaultWrappedAt:)`), to the latest of the stamp, now and the vault's wrap time, and saves it every
/// time. A wrap is always at least now as well. Then the stamp is always about when the device was last unlocked, like
/// the file's modification time. It also means that after a restore onto a new device, where the stamp isn't
/// restored, wraps made once the user has opened a vault there follow that vault's.
///
/// What's left: on a device whose stamp is missing, or older than the real vault's wrap, a duress vault made before the
/// user has opened the real vault there is stamped only after the clock and the duress vault it's made from, so a
/// clock set back can still make it older than the real vault.
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

    /// Moves the stamp to the latest of itself, now and `wrappedAt`, and saves it, for a vault that's just opened:
    /// every time, whether or not it moves, so the work is the same whatever the stamp was.
    ///
    /// - Parameter wrappedAt: The wrap time of the vault that opened, so wraps made from now on follow it.
    /// - Throws: If the stamp couldn't be read or saved.
    public func noteUse(ofVaultWrappedAt wrappedAt: Date) throws {
        try lock.modify { _ in
            var stamp = max(Self.milliseconds(since1970: currentDate()), Self.milliseconds(since1970: wrappedAt))
            if let saved = try storage.load() {
                stamp = max(stamp, saved)
            }
            try storage.save(stamp)
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
    /// Removes the stamp, for erasing (VAULT-52). Does nothing if there isn't one.
    func remove() throws
}

/// Keeps the wrap stamp in the keychain, on this device only, in the keychain access group the app shares with the
/// AutoFill extension only (`SharedKeychainItem`).
///
/// It survives relaunches and updates. It never syncs to iCloud Keychain and never moves to another device with a
/// backup, so a stamp from another time can't be put back with an old backup.
struct VaultWrapStampKeychainStorage: VaultWrapStampStorage {
    let item: SharedKeychainItem

    init(item: SharedKeychainItem = SharedKeychainItem(key: .vaultWrapStamp)) {
        self.item = item
    }

    func load() throws -> UInt64? {
        guard let data = try item.data() else { return nil }
        return try JSONDecoder().decode(UInt64.self, from: data)
    }

    func save(_ stamp: UInt64) throws {
        try item.save(Self.attributes(for: stamp))
    }

    func remove() throws {
        try item.remove()
    }

    /// Moves the stamp out of the App Group's keychain access group, where versions before VAULT-129 kept it
    /// (`SharedKeychainItem.moveFromTheAppGroup()`).
    func moveFromTheAppGroup() throws {
        try item.moveFromTheAppGroup()
    }

    /// What's stored in the item: the stamp, readable only while the device is unlocked, on this device only.
    static func attributes(for stamp: UInt64) throws -> [String: Any] {
        try [
            kSecValueData as String: JSONEncoder().encode(stamp),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }
}
