import Foundation
import Security
import SwiftSecurity

/// What `AppLockPasswordAttemptCounter` keeps between launches.
///
/// A record saved while the counter also kept a recent count of wrong attempts has `recentWrong` and `recentWrongAt`
/// as well. Decoding ignores them, so it reads as its attempts in a row.
struct AppLockPasswordAttemptRecord: Codable, Equatable {
    /// Attempts at the password in a row: since one last opened a vault, whichever vault it was. An attempt still
    /// underway counts, and so does one the app was stopped in the middle of. It decides the delay, and when to erase
    /// (VAULT-34).
    var count: Int
    /// When the latest attempt was counted, by the app lock's clock. The delay before the next one runs from here.
    var latestAt: ContinuousClock.Instant
}

/// Where `AppLockPasswordAttemptCounter` keeps its record.
///
/// Synchronous, so that the counter reads, updates and writes the record without pausing in between: two attempts
/// counted at once in the same process can't both see the same count. `acquireExclusiveAccess()` does the same across
/// processes, for the app and the AutoFill extension running side by side, as they can on an iPad.
protocol AppLockPasswordAttemptStorage: Sendable {
    /// The record, or `nil` if there isn't one: no attempts since the password was last entered correctly.
    func load() throws -> AppLockPasswordAttemptRecord?
    /// Replaces the record. It's in storage by the time this returns.
    func save(_ record: AppLockPasswordAttemptRecord) throws
    /// Removes the record. Does nothing if there isn't one.
    func remove() throws
    /// Keeps other processes from reading or writing the record until the access is released, waiting first for any
    /// that has it.
    func acquireExclusiveAccess() async throws -> AppLockPasswordAttemptAccess
    /// Removes whatever `acquireExclusiveAccess()` leaves on disk, if anything. The next access makes it again.
    func removeLockFile() throws
}

extension AppLockPasswordAttemptStorage {
    /// Storage no other process shares needs no more than the counter's own isolation.
    func acquireExclusiveAccess() async throws -> AppLockPasswordAttemptAccess {
        AppLockPasswordAttemptAccess {}
    }

    /// Storage no other process shares leaves nothing on disk to take a lock on.
    func removeLockFile() throws {}
}

/// Exclusive access to the attempt record. Release it exactly once.
struct AppLockPasswordAttemptAccess: Sendable {
    let release: @Sendable () -> Void
}

/// Keeps the password attempt record in the keychain, on this device only.
///
/// The keychain outlives the app: relaunching it, or installing a new version over the top, keeps the count. The item
/// is readable only while the device is unlocked, never syncs to iCloud Keychain, and never moves to another device
/// with a backup. It's in the keychain access group the app shares with the AutoFill extension only
/// (`SharedKeychainItem`), so the AutoFill extension can count attempts made there against the same record, and the
/// widget extension can't read it.
///
/// This talks to the keychain directly, rather than through `SecureStorage`, so that it can update the item in
/// place. `SecureStorage` removes an item and then adds it again, and an app stopped in between would forget every
/// wrong attempt.
struct AppLockPasswordAttemptKeychainStorage: AppLockPasswordAttemptStorage {
    let item: SharedKeychainItem
    /// The file whose lock the app and its extensions take around each change to the record.
    private let lockFileURL: @Sendable () -> URL
    /// How long to wait for another process to let go of the lock before giving up.
    private let lockTimeout: Duration

    /// The lock file's name, in the App Group's storage directory.
    static let lockFileName = "app-lock-password-attempts.lock"

    init(
        item: SharedKeychainItem = SharedKeychainItem(key: .appLockPasswordAttempts),
        lockFileURL: @escaping @Sendable () -> URL = {
            VaultSharedStorage.directory().appending(path: lockFileName)
        },
        lockTimeout: Duration = .seconds(5),
    ) {
        self.item = item
        self.lockFileURL = lockFileURL
        self.lockTimeout = lockTimeout
    }

    static let lockRetryInterval = Duration.milliseconds(2)

    /// Takes an exclusive `flock` on the lock file, which every process holds only while it reads and writes the
    /// keychain item. While another has it, it tries again every couple of milliseconds, without blocking a thread,
    /// for up to `lockTimeout`, then throws.
    func acquireExclusiveAccess() async throws -> AppLockPasswordAttemptAccess {
        let descriptor = open(lockFileURL().path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(Self.errorCode(errno)) }
        let deadline = ContinuousClock.now + lockTimeout
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let error = errno
            if error == EINTR {
                continue
            }
            guard error == EWOULDBLOCK, ContinuousClock.now < deadline else {
                close(descriptor)
                throw POSIXError(Self.errorCode(error))
            }
            do {
                try await Task.sleep(for: Self.lockRetryInterval)
            } catch {
                close(descriptor)
                throw error
            }
        }
        return AppLockPasswordAttemptAccess {
            close(descriptor)
        }
    }

    /// Removes the lock file, if it's there. Only an erase does, once there's no password left to count attempts at:
    /// the file shows one was tried on this device. Setting a password makes it again.
    func removeLockFile() throws {
        guard unlink(lockFileURL().path) == 0 else {
            let error = errno
            guard error != ENOENT else { return }
            throw POSIXError(Self.errorCode(error))
        }
    }

    private static func errorCode(_ error: Int32) -> POSIXErrorCode {
        POSIXErrorCode(rawValue: error) ?? .EIO
    }

    func load() throws -> AppLockPasswordAttemptRecord? {
        guard let data = try item.data() else { return nil }
        return try JSONDecoder().decode(AppLockPasswordAttemptRecord.self, from: data)
    }

    func save(_ record: AppLockPasswordAttemptRecord) throws {
        try item.save(Self.attributes(for: record))
    }

    func remove() throws {
        try item.remove()
    }

    /// Moves the record out of the App Group's keychain access group, where versions before VAULT-129 kept it
    /// (`SharedKeychainItem.moveFromTheAppGroup()`), holding the lock, so no attempt is counted or forgotten meanwhile,
    /// in this process or another. The lock is only taken if there's a record to move, as its file shows a password
    /// was tried on this device (`removeLockFile()`).
    func moveFromTheAppGroup() async throws {
        guard try item.isInTheAppGroup() else { return }
        let access = try await acquireExclusiveAccess()
        defer { access.release() }
        try item.moveFromTheAppGroup()
    }

    /// What's stored in the item: the record, readable only while the device is unlocked, on this device only.
    static func attributes(for record: AppLockPasswordAttemptRecord) throws -> [String: Any] {
        try [
            kSecValueData as String: JSONEncoder().encode(record),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }
}
