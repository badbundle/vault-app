import Foundation
import Security
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check what
/// `AppLockPasswordAttemptKeychainStorage` would ask it for.
struct AppLockPasswordAttemptKeychainStorageTests {
    @Test
    func init_sharesTheItemWithTheExtensions() {
        let sut = AppLockPasswordAttemptKeychainStorage()

        #expect(sut.accessGroup == VaultSharedStorage.appGroupID)
    }

    @Test
    func itemQuery_matchesTheAttemptRecordInTheAccessGroup() {
        let query = AppLockPasswordAttemptKeychainStorage.itemQuery(accessGroup: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        let service = query[kSecAttrService as String] as? String
        #expect(service == VaultIdentifiers.SecureStorageKey.appLockPasswordAttempts.rawValue)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
    }

    /// A count that synced to iCloud Keychain could be reset from another device.
    @Test
    func itemQuery_neverSyncs() {
        let query = AppLockPasswordAttemptKeychainStorage.itemQuery(accessGroup: nil)

        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    }

    @Test
    func attributes_keepTheItemOnThisDeviceWhileUnlocked() throws {
        let attributes = try AppLockPasswordAttemptKeychainStorage.attributes(for: anyRecord())

        let accessible = attributes[kSecAttrAccessible as String] as? String
        #expect(accessible == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    @Test
    func attributes_holdTheRecord() throws {
        let record = anyRecord()

        let attributes = try AppLockPasswordAttemptKeychainStorage.attributes(for: record)

        let data = try #require(attributes[kSecValueData as String] as? Data)
        #expect(try JSONDecoder().decode(AppLockPasswordAttemptRecord.self, from: data) == record)
    }

    /// Another process opening the lock file can't take the lock while a change is underway, and can straight after.
    @Test
    func acquireExclusiveAccess_locksOutOtherProcessesMeanwhile() async throws {
        let lockFile = Self.temporaryLockFile()
        defer { try? FileManager.default.removeItem(at: lockFile) }
        let sut = AppLockPasswordAttemptKeychainStorage(accessGroup: nil, lockFileURL: { lockFile })

        let access = try await sut.acquireExclusiveAccess()
        let lockedMeanwhile = !Self.canLock(lockFile)
        access.release()

        #expect(lockedMeanwhile)
        #expect(Self.canLock(lockFile))
    }

    /// While another process has the lock, it waits for it, without blocking a thread.
    @Test
    func acquireExclusiveAccess_waitsForAnotherProcessToLetGo() async throws {
        let lockFile = Self.temporaryLockFile()
        defer { try? FileManager.default.removeItem(at: lockFile) }
        // Long enough for the other process to let go on a busy machine.
        let sut = AppLockPasswordAttemptKeychainStorage(
            accessGroup: nil,
            lockFileURL: { lockFile },
            lockTimeout: .seconds(60),
        )
        let other = try Self.holdLock(on: lockFile)
        let letGo = Task {
            try? await Task.sleep(for: .milliseconds(50))
            close(other)
        }

        let access = try await sut.acquireExclusiveAccess()

        access.release()
        await letGo.value
    }

    /// It doesn't wait forever for a process that never lets go.
    @Test
    func acquireExclusiveAccess_givesUpAfterTheTimeout() async throws {
        let lockFile = Self.temporaryLockFile()
        defer { try? FileManager.default.removeItem(at: lockFile) }
        let sut = AppLockPasswordAttemptKeychainStorage(
            accessGroup: nil,
            lockFileURL: { lockFile },
            lockTimeout: .milliseconds(20),
        )
        let other = try Self.holdLock(on: lockFile)
        defer { close(other) }

        await #expect(throws: POSIXError.self) {
            try await sut.acquireExclusiveAccess()
        }
    }

    private static func temporaryLockFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).lock")
    }

    /// Takes the lock as another process would, through a separate open of the file.
    private static func holdLock(on url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_RDWR | O_CREAT, 0o600)
        try #require(descriptor >= 0)
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        return descriptor
    }

    /// Whether a separate open of the file, as another process would make, can take its lock now.
    private static func canLock(_ url: URL) -> Bool {
        let descriptor = open(url.path, O_RDWR)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }

    private func anyRecord() -> AppLockPasswordAttemptRecord {
        AppLockPasswordAttemptRecord(count: 7, latestAt: .now)
    }
}
