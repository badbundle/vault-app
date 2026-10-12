import Foundation
import FoundationExtensions
import Security
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check what
/// `AppLockPasswordAttemptKeychainStorage` would ask it for, and run it on a keychain in memory.
struct AppLockPasswordAttemptKeychainStorageTests {
    /// The AutoFill extension counts against the same record as the app, and the widget extension can't read it
    /// (VAULT-129).
    @Test
    func init_sharesTheItemWithAutoFillOnly() {
        let sut = AppLockPasswordAttemptKeychainStorage()

        #expect(sut.item.accessGroup == VaultSharedStorage.keychainGroupID)
        #expect(sut.item.formerAccessGroup == VaultSharedStorage.appGroupID)
    }

    @Test
    func itemQuery_matchesTheAttemptRecordInTheAccessGroup() {
        let query = AppLockPasswordAttemptKeychainStorage().item.query(in: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        let service = query[kSecAttrService as String] as? String
        #expect(service == VaultIdentifiers.SecureStorageKey.appLockPasswordAttempts.rawValue)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
    }

    /// A count that synced to iCloud Keychain could be reset from another device.
    @Test
    func itemQuery_neverSyncs() {
        let query = AppLockPasswordAttemptKeychainStorage().item.query(in: nil)

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
        let sut = AppLockPasswordAttemptKeychainStorage(lockFileURL: { lockFile })

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
            lockFileURL: { lockFile },
            lockTimeout: .milliseconds(20),
        )
        let other = try Self.holdLock(on: lockFile)
        defer { close(other) }

        await #expect(throws: POSIXError.self) {
            try await sut.acquireExclusiveAccess()
        }
    }

    // MARK: - In the keychain

    @Test
    func saveAndLoad_keepTheRecordInTheSharedGroup() throws {
        let keychain = InMemoryKeychain()
        let sut = Self.storage(on: keychain)
        let record = anyRecord()

        try sut.save(record)

        #expect(try sut.load() == record)
        #expect(keychain.item(.appLockPasswordAttempts, in: VaultSharedStorage.keychainGroupID) != nil)
        #expect(keychain.item(.appLockPasswordAttempts, in: VaultSharedStorage.appGroupID) == nil)
    }

    /// A record an earlier version kept in the App Group's access group is counted on from until it's moved.
    @Test
    func load_recordStillInTheAppGroup_isReadFromThere() throws {
        let keychain = InMemoryKeychain()
        let record = anyRecord()
        try Self.putInTheAppGroup(record, on: keychain)

        #expect(try Self.storage(on: keychain).load() == record)
    }

    @Test
    func remove_deletesTheRecordFromBothGroups() throws {
        let keychain = InMemoryKeychain()
        let sut = Self.storage(on: keychain)
        try Self.putInTheAppGroup(anyRecord(), on: keychain)
        try sut.save(anyRecord())

        try sut.remove()

        #expect(try sut.load() == nil)
        #expect(keychain.item(.appLockPasswordAttempts, in: VaultSharedStorage.appGroupID) == nil)
        #expect(keychain.item(.appLockPasswordAttempts, in: VaultSharedStorage.keychainGroupID) == nil)
    }

    /// The record moves holding the lock, so no attempt is counted or forgotten in another process meanwhile.
    @Test
    func moveFromTheAppGroup_movesTheRecordHoldingTheLock() async throws {
        let lockFile = Self.temporaryLockFile()
        defer { try? FileManager.default.removeItem(at: lockFile) }
        let keychain = InMemoryKeychain()
        let record = anyRecord()
        try Self.putInTheAppGroup(record, on: keychain)
        let lockedWhileMoving = SharedMutex<Bool?>(nil)
        keychain.beforeEachCall { call in
            guard call == .add(group: VaultSharedStorage.keychainGroupID) else { return }
            lockedWhileMoving.modify { $0 = !Self.canLock(lockFile) }
        }
        let sut = Self.storage(on: keychain, lockFile: lockFile)

        try await sut.moveFromTheAppGroup()

        #expect(lockedWhileMoving.value == true)
        #expect(Self.canLock(lockFile))
        #expect(keychain.item(.appLockPasswordAttempts, in: VaultSharedStorage.appGroupID) == nil)
        #expect(try sut.load() == record)
    }

    /// The lock file shows a password was tried on this device, so a launch with nothing to move doesn't make it.
    @Test
    func moveFromTheAppGroup_withNothingToMove_leavesNoLockFile() async throws {
        let lockFile = Self.temporaryLockFile()
        defer { try? FileManager.default.removeItem(at: lockFile) }
        let sut = Self.storage(on: InMemoryKeychain(), lockFile: lockFile)

        try await sut.moveFromTheAppGroup()

        #expect(!FileManager.default.fileExists(atPath: lockFile.path))
    }

    /// Moving never resets or lowers the count: the next attempt counts on from the moved record.
    @Test
    func counter_afterTheRecordMoves_countsOnFromIt() async throws {
        let lockFile = Self.temporaryLockFile()
        defer { try? FileManager.default.removeItem(at: lockFile) }
        let keychain = InMemoryKeychain()
        let clock = FakeAppLockClock()
        try Self.putInTheAppGroup(AppLockPasswordAttemptRecord(count: 3, latestAt: clock.now), on: keychain)
        let storage = Self.storage(on: keychain, lockFile: lockFile)
        let counter = AppLockPasswordAttemptCounter(storage: storage, clock: clock)

        try await storage.moveFromTheAppGroup()

        #expect(try await counter.countAttempt() == .counted(reachesEraseThreshold: false))
        #expect(try storage.load()?.count == 4)
    }

    /// A move that fails leaves the record where it was, still counted on from, and the next move finishes.
    @Test
    func counter_whenTheMoveFails_countsOnFromTheAppGroupsRecord() async throws {
        let lockFile = Self.temporaryLockFile()
        defer { try? FileManager.default.removeItem(at: lockFile) }
        let keychain = InMemoryKeychain()
        let clock = FakeAppLockClock()
        try Self.putInTheAppGroup(AppLockPasswordAttemptRecord(count: 3, latestAt: clock.now), on: keychain)
        let storage = Self.storage(on: keychain, lockFile: lockFile)
        let counter = AppLockPasswordAttemptCounter(storage: storage, clock: clock)
        keychain.fail(.add(group: VaultSharedStorage.keychainGroupID))

        await #expect(throws: (any Error).self) {
            try await storage.moveFromTheAppGroup()
        }
        #expect(try storage.load()?.count == 3)
        keychain.fail(.add(group: VaultSharedStorage.keychainGroupID), with: nil)
        #expect(try await counter.countAttempt() == .counted(reachesEraseThreshold: false))
        try await storage.moveFromTheAppGroup()

        #expect(try storage.load()?.count == 4)
        #expect(keychain.item(.appLockPasswordAttempts, in: VaultSharedStorage.appGroupID) == nil)
    }

    private static func storage(
        on keychain: InMemoryKeychain,
        lockFile: URL = temporaryLockFile(),
    ) -> AppLockPasswordAttemptKeychainStorage {
        AppLockPasswordAttemptKeychainStorage(
            item: SharedKeychainItem(key: .appLockPasswordAttempts, keychain: keychain),
            lockFileURL: { lockFile },
        )
    }

    /// Puts `record` where versions before VAULT-129 kept it.
    private static func putInTheAppGroup(_ record: AppLockPasswordAttemptRecord, on keychain: InMemoryKeychain) throws {
        let data = try #require(AppLockPasswordAttemptKeychainStorage.attributes(for: record)[kSecValueData as String]
            as? Data)
        keychain.set(.init(data: data), for: .appLockPasswordAttempts, in: VaultSharedStorage.appGroupID)
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
