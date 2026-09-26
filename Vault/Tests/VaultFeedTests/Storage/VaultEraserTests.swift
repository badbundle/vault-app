import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

/// Erasing every vault, from every kind of device, and finishing an erase that failed or crashed part way.
struct VaultEraserTests {
    /// The usual case: after too many wrong passwords at the lock screen, with the vault locked. The device has
    /// everything an erase removes: the encrypted file, the plain store's files as a conversion that was interrupted
    /// left them, an archive, pending rehash files, temp files, the keychain items and the count of wrong attempts.
    @Test
    func erase_fromALockedPasswordVault_leavesAFreshEmptyPlainStoreAndNoKeys() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
            await harness.session.lock()

            try await harness.erase()

            try await harness.expectErased()
            #expect(await !harness.session.isLocked)
            #expect(try await harness.session.retrieve(query: .init()).items.isEmpty)
            #expect(try await harness.session.retrieveTags().isEmpty)
            #expect(try harness.stepsInOrder([
                "lock vault-slots.lock",
                "remove vault-slots.v1",
                "remove the killphrase key from the keychain",
                "reset the attempt count",
                "clear QuickType",
                "reload widgets",
                "create the plain store",
                "remove vault-storage-state.json",
            ]))
        }
    }

    /// The encrypted file goes before anything else an erase removes: that alone makes every vault unreadable.
    @Test
    func erase_removesTheEncryptedFileFirst() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try await VaultEraseHarness.encryptedDevice(in: directory)

            try await harness.erase()

            let removals = harness.fileSystem.log.filter { $0.hasPrefix("remove ") }
            #expect(removals.first == "remove vault-slots.v1")
        }
    }

    /// Erasing with a vault open locks it first. The store that had it open can't save it back afterwards.
    @Test
    func erase_fromAnUnlockedVault_locksItAndItsStoreCantSaveItBack() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
            let openStore = try await harness.openEncryptedStore()

            try await harness.erase()

            try await harness.expectErased()
            await #expect(throws: EncryptedVaultStoreError.fileMissing) {
                try await openStore.insert(item: uniqueVaultItem().makeWritable())
            }
            #expect(try !harness.fileNames().contains(EncryptedVaultFile.fileName))
        }
    }

    /// The erase doesn't depend on which vault is open: a real vault and a duress vault in the same file erase with
    /// exactly the same steps, and leave the same fresh store.
    @Test
    func erase_fromEitherOfTwoVaults_takesTheSameStepsAndErasesBoth() async throws {
        try await withTemporaryDirectory { first in
            try await withTemporaryDirectory { second in
                let real = try EncryptedVaultFixture(fileSystem: LiveSlotFileSystem(), directory: first, slotIndex: 3)
                let duress = try await real.addingVault(inSlot: 11)
                try FileManager.default.copyItem(
                    at: first.appending(path: EncryptedVaultFile.fileName),
                    to: second.appending(path: EncryptedVaultFile.fileName),
                )
                let erasingReal = try await VaultEraseHarness.device(in: first, unlocking: real)
                let erasingDuress = try await VaultEraseHarness.device(in: second, unlocking: duress)

                try await erasingReal.erase()
                try await erasingDuress.erase()

                #expect(erasingReal.fileSystem.log == erasingDuress.fileSystem.log)
                try await erasingReal.expectErased()
                try await erasingDuress.expectErased()
            }
        }
    }

    /// With no encrypted vault at all, it erases the plain store, once it's let go of it.
    @Test
    func erase_fromThePlainStore_deletesItAndStartsAFreshOne() async throws {
        try await withTemporaryDirectory { directory in
            let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
            try await VaultEncryptionConverterTests.seed(store)
            let harness = VaultEraseHarness(directory: directory, session: VaultStoreSession(target: .plain(store)))
            try await harness.seedKeychain()

            try await harness.erase()

            #expect(try harness.stepsInOrder(["release the plain store", "remove vault-primary.sqlite"]))
            try await harness.expectErased()
            #expect(try await harness.session.retrieve(query: .init()).items.isEmpty)
        }
    }

    /// With nothing to erase, it still leaves a fresh plain store and the journal cleared, and it can be repeated.
    @Test
    func erase_withNothingToErase_twice_leavesAFreshPlainStore() async throws {
        try await withTemporaryDirectory { directory in
            let harness = VaultEraseHarness(directory: directory)

            try await harness.erase()
            try await harness.erase()

            try await harness.expectErased()
        }
    }

    /// A second call while an erase is underway waits for it, rather than starting another.
    @Test
    func erase_calledAgainWhileErasing_erasesOnce() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
            let eraser = harness.makeEraser()

            async let first: Void = eraser.erase()
            async let second: Void = eraser.erase()
            _ = try await (first, second)

            #expect(harness.fileSystem.log.count { $0 == "clear QuickType" } == 1)
            try await harness.expectErased()
        }
    }
}

// MARK: - Failures and crashes

extension VaultEraserTests {
    /// Every step of an erase from a device with everything to erase.
    private struct Steps {
        var names: [String]
        /// Renaming the journal into place. A crash up to here stops the erase before it's journaled or anything is
        /// removed, so the next launch finds the vault as it was.
        var journalRename: Int
    }

    private static func stepsOfAnErase() async throws -> Steps {
        try await withTemporaryDirectory { directory in
            let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
            try await harness.erase()
            let names = harness.steps()
            let journalRename = try #require(names.firstIndex(of: "rename state temp to vault-storage-state.json")) + 1
            #expect(names.prefix(journalRename).allSatisfy { !$0.hasPrefix("remove") })
            // Crashes and failures in the keychain and creating the fresh store are covered too.
            for step in [
                "remove the backup password from the keychain",
                "reset the attempt count",
                "create the plain store",
            ] {
                #expect(names.contains(step))
            }
            return Steps(names: names, journalRename: journalRename)
        }
    }

    /// Whichever step fails, no vault is left readable: the encrypted file is gone once the erase returns. A failure
    /// to journal doesn't stop it. A failure after that stops it with the vault locked, and erasing again finishes.
    @Test
    func erase_failingAtAnyStep_leavesNoVaultAndErasingAgainFinishes() async throws {
        let steps = try await Self.stepsOfAnErase()
        for step in 1 ... steps.names.count {
            try await withTemporaryDirectory { directory in
                let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
                await harness.session.lock()
                harness.fileSystem.inject(.fail(atStep: step))

                let result = await Result(asyncThrowingClosure: { try await harness.erase() })

                let context = Comment(rawValue: "failing at step \(step), \(steps.names[step - 1])")
                #expect(try !harness.fileNames().contains(EncryptedVaultFile.fileName), context)
                if case .failure = result {
                    #expect(await harness.session.isLocked, context)
                }
                harness.fileSystem.inject(nil)
                try await harness.erase()
                try await harness.expectErased(context)
            }
        }
    }

    /// The app stops at any step. If the erase was journaled by then, the next launch finishes it, leaving a fresh
    /// empty plain store and no keychain items. If it wasn't, nothing was removed, and the vault is as it was.
    @Test
    func erase_crashingAtAnyStep_isFinishedByTheNextLaunch() async throws {
        let steps = try await Self.stepsOfAnErase()
        for step in 1 ... steps.names.count {
            try await withTemporaryDirectory { directory in
                let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
                let before = try harness.encryptedFileBytes()
                harness.fileSystem.inject(.crash(atStep: step))

                _ = try? await harness.erase()
                let journaled = step > steps.journalRename
                let context = Comment(rawValue: "crashing at step \(step), \(steps.names[step - 1])")
                if journaled, try harness.stateFile.read().transition == .erasing {
                    // Until it finishes, the extensions treat the vault as locked.
                    #expect(!VaultStorageState.isPlain(inDirectory: directory), context)
                }
                let outcome = try await harness.relaunch()

                if journaled {
                    #expect(outcome != .password, context)
                    try await harness.expectErased(context)
                } else {
                    #expect(outcome == .password, context)
                    #expect(try harness.encryptedFileBytes() == before, context)
                    #expect(await harness.keychain.keys() == Set(VaultEraser.keychainKeys), context)
                    #expect(harness.attemptStorage.hasRecord, context)
                }
            }
        }
    }
}

// MARK: - Harness

/// A device to erase: its storage directory, keychain and count of wrong attempts, and a store session.
///
/// Every file operation, keychain removal and plain store creation an erase makes is a step of `fileSystem`, which
/// can make it fail or crash. Hooks are recorded in its log too, in order with the steps.
struct VaultEraseHarness {
    static let hookEntries: Set = ["release the plain store", "clear QuickType", "reload widgets"]
    /// Text from the vault that must be in no file once it's erased.
    static let plaintextMarkers = ["Bank", plaintext].map { Data($0.utf8) }
    /// What the plain store's leftover files, the rehash files and the temp files hold.
    static let plaintext = "ERASED-VAULT-PLAINTEXT"

    let directory: URL
    let fileSystem: FaultInjectingSlotFileSystem
    let keychain: FaultInjectingSecureStorage
    let attemptStorage: FaultInjectingAttemptStorage
    let session: VaultStoreSession

    init(directory: URL, session: VaultStoreSession = VaultStoreSession(target: .locked)) {
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: LiveSlotFileSystem())
        self.directory = directory
        self.fileSystem = fileSystem
        keychain = FaultInjectingSecureStorage(faults: fileSystem)
        attemptStorage = FaultInjectingAttemptStorage(faults: fileSystem)
        self.session = session
    }

    /// A device with an encrypted vault, as a conversion leaves it, with its session unlocked on it, and everything
    /// else an erase removes:
    ///
    /// - the plain store's files, an archive and pending rehash files, as if deleting them after the conversion had
    ///   been interrupted, with the journal still saying so;
    /// - temp files left by crashes while writing the encrypted file and the storage state;
    /// - every keychain item, and ten wrong attempts in a row.
    static func encryptedDevice(in directory: URL) async throws -> VaultEraseHarness {
        let conversion = try PlainVaultConversionHarness(directory: directory)
        try await VaultEncryptionConverterTests.seed(conversion.store)
        try await conversion.encrypt()

        for name in VaultStorageRecoveryTests.plainStoreNames {
            try Data(plaintext.utf8).write(to: directory.appending(path: name))
        }
        for url in PersistedLocalVaultStoreFactory.pendingRehashFileURLs(storageDirectory: directory) {
            try Data(plaintext.utf8).write(to: url)
        }
        let archive = try VaultEncryptionConverterTests.makeArchive(in: directory)
        var state = try conversion.stateFile.read()
        state.transition = .deletingPlainStore(archives: [archive.lastPathComponent])
        try conversion.stateFile.write(state)
        try Data(plaintext.utf8).write(to: directory.appending(path: EncryptedVaultFile.temporaryFilePrefix + "a"))
        try Data("{}".utf8).write(to: directory.appending(path: VaultStorageStateFile.temporaryFilePrefix + "a"))

        let harness = VaultEraseHarness(directory: directory, session: conversion.session)
        try await harness.seedKeychain()
        return harness
    }

    /// A device whose encrypted file is already in `directory`, with its session unlocked on `vault`.
    static func device(in directory: URL, unlocking vault: EncryptedVaultFixture) async throws -> VaultEraseHarness {
        let file = EncryptedVaultFile(directory: directory)
        let contents = try #require(try await file.open())
        let store = try EncryptedVaultStore(
            file: file,
            contents: contents,
            slot: contents.openSlot(vault.slotIndex, with: vault.rootKey),
        )
        let harness = VaultEraseHarness(directory: directory, session: VaultStoreSession(target: .unlocked(store)))
        try await harness.seedKeychain()
        return harness
    }

    /// Puts every keychain item an erase deletes in the keychain, and ten wrong attempts in a row.
    func seedKeychain() async throws {
        for key in VaultEraser.keychainKeys {
            await keychain.store(data: Data(key.utf8), forKey: key)
        }
        attemptStorage.setCount(AppLockPasswordAttemptCounter.eraseThreshold)
    }

    /// An eraser, as the app makes one.
    func makeEraser() -> VaultEraser {
        let fileSystem = fileSystem
        let directory = directory
        return VaultEraser(
            directory: directory,
            fileSystem: fileSystem,
            session: session,
            secureStorage: keychain,
            attemptCounter: AppLockPasswordAttemptCounter(storage: attemptStorage, clock: FakeAppLockClock()),
            hooks: VaultEraser.Hooks(
                releasePlainStore: { fileSystem.record("release the plain store") },
                clearCredentialIdentities: { fileSystem.record("clear QuickType") },
                reloadWidgets: { fileSystem.record("reload widgets") },
            ),
            makePlainStore: {
                try fileSystem.step("create the plain store")
                return try PersistedLocalVaultStoreFactory(storageDirectory: directory, recoveryMode: .openOnly)
                    .makeVaultStoreOrThrow()
            },
        )
    }

    func erase() async throws {
        try await makeEraser().erase()
    }

    /// Launches again: recovers as the app does at launch, and if an erase is to finish, finishes it with a new
    /// eraser, as `VaultRoot.setup()` does.
    func relaunch() async throws -> VaultStorageRecovery.Outcome {
        fileSystem.inject(nil)
        let outcome = try VaultStorageRecovery(directory: directory).recoverAtLaunch()
        if outcome == .erasing {
            try await erase()
        }
        return outcome
    }

    /// Opens the encrypted vault with the password, as the unlock service does.
    func openEncryptedStore() async throws -> EncryptedVaultStore {
        let file = EncryptedVaultFile(directory: directory)
        let contents = try #require(try await file.open())
        let key = try contents.header.passwordKey(for: PlainVaultConversionHarness.password)
        let slot = try #require(VaultSlotFile.slotIndices.lazy.compactMap { try? contents.openSlot($0, with: key) }
            .first)
        return try EncryptedVaultStore(file: file, contents: contents, slot: slot)
    }

    // MARK: - What happened

    /// The steps taken so far, without the hooks, which aren't steps.
    func steps() -> [String] {
        fileSystem.log.filter { $0 != "unlock" && !Self.hookEntries.contains($0) }
    }

    /// Whether the log has these entries in this order, with others in between.
    func stepsInOrder(_ entries: [String]) throws -> Bool {
        var remaining = entries[...]
        for entry in fileSystem.log where entry == remaining.first {
            remaining = remaining.dropFirst()
        }
        return remaining.isEmpty
    }

    var stateFile: VaultStorageStateFile {
        VaultStorageStateFile(directory: directory, fileSystem: LiveSlotFileSystem())
    }

    func fileNames() throws -> Set<String> {
        try VaultStorageRecoveryTests.fileNames(in: directory)
    }

    func encryptedFileBytes() throws -> Data {
        try Data(contentsOf: directory.appending(path: EncryptedVaultFile.fileName))
    }

    /// Only a fresh, empty plain store is left: no other file, nothing of the old vault in it, no keychain item, no
    /// count of attempts, and nothing underway.
    func expectErased(_ context: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let names = try fileNames()
        #expect(names.contains("vault-primary.sqlite"), context, sourceLocation: sourceLocation)
        #expect(names.isSubset(of: VaultStorageRecoveryTests.plainStoreNames), context, sourceLocation: sourceLocation)
        for name in names {
            let contents = try Data(contentsOf: directory.appending(path: name))
            for marker in Self.plaintextMarkers where contents.range(of: marker) != nil {
                Issue.record("Found the erased vault in \(name)", sourceLocation: sourceLocation)
            }
        }

        let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory, recoveryMode: .openOnly)
            .makeVaultStoreOrThrow()
        let state = try await store.recordState()
        #expect(state.items.isEmpty, context, sourceLocation: sourceLocation)
        #expect(state.tags.isEmpty, context, sourceLocation: sourceLocation)

        #expect(await keychain.keys().isEmpty, context, sourceLocation: sourceLocation)
        #expect(!attemptStorage.hasRecord, context, sourceLocation: sourceLocation)
        #expect(VaultStorageState.isPlain(inDirectory: directory), context, sourceLocation: sourceLocation)
        #expect(try VaultStorageRecovery(directory: directory).recoverAtLaunch() == .plain, context)
    }
}

/// A keychain in memory whose removals are steps of a `FaultInjectingSlotFileSystem`.
actor FaultInjectingSecureStorage: SecureStorage {
    private var items = [String: Data]()
    private let faults: FaultInjectingSlotFileSystem

    init(faults: FaultInjectingSlotFileSystem) {
        self.faults = faults
    }

    func keys() -> Set<String> {
        Set(items.keys)
    }

    func store(data: Data, forKey key: String) {
        items[key] = data
    }

    func retrieve(key: String) -> Data? {
        items[key]
    }

    func storeSilent(data: Data, forKey key: String) {
        items[key] = data
    }

    func retrieveSilent(key: String) -> Data? {
        items[key]
    }

    func attributes(key: String) -> SecureStorageAttributes? {
        items[key].map { _ in SecureStorageAttributes(modificationDate: nil) }
    }

    func remove(key: String) throws {
        try faults.step("remove \(Self.name(key)) from the keychain")
        items[key] = nil
    }

    private static func name(_ key: String) -> String {
        switch key {
        case VaultIdentifiers.SecureStorageKey.killphraseKey: "the killphrase key"
        case VaultIdentifiers.SecureStorageKey.searchPassphraseKey: "the search passphrase key"
        case VaultIdentifiers.SecureStorageKey.backupPassword: "the backup password"
        case VaultIdentifiers.SecureStorageKey.backupPasswordMetadata: "the backup password's record"
        default: key
        }
    }
}

/// The count of wrong attempts in memory, whose removal is a step of a `FaultInjectingSlotFileSystem`.
final class FaultInjectingAttemptStorage: AppLockPasswordAttemptStorage {
    private let record = SharedMutex<AppLockPasswordAttemptRecord?>(nil)
    private let faults: FaultInjectingSlotFileSystem

    init(faults: FaultInjectingSlotFileSystem) {
        self.faults = faults
    }

    var hasRecord: Bool {
        record.get { $0 != nil }
    }

    func setCount(_ count: Int) {
        record.modify { $0 = AppLockPasswordAttemptRecord(count: count, latestAt: .now) }
    }

    func load() throws -> AppLockPasswordAttemptRecord? {
        record.get { $0 }
    }

    func save(_ newRecord: AppLockPasswordAttemptRecord) throws {
        record.modify { $0 = newRecord }
    }

    func remove() throws {
        try faults.step("reset the attempt count")
        record.modify { $0 = nil }
    }
}
