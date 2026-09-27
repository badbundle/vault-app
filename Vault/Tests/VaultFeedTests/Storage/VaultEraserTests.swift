import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

/// Erasing every vault, from every kind of device, and finishing an erase that failed or crashed part way.
@MainActor
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
                "remove the wrap stamp",
                "forget the vault's settings",
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

    /// The lock file goes after the encrypted file, including when the journal couldn't be written and the plain store
    /// goes first. A writer that found no lock file would make a new one and take it at once, and could save over an
    /// encrypted file that was still there.
    @Test(arguments: [false, true])
    func erase_removesTheLockFileAfterTheEncryptedFile(journalFails: Bool) async throws {
        try await withTemporaryDirectory { directory in
            let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
            if journalFails {
                // Creating the journal's temp file, the second step.
                harness.fileSystem.inject(.fail(atStep: 2))
            }

            try await harness.erase()

            let log = harness.fileSystem.log
            let encryptedFile = try #require(log.firstIndex(of: "remove vault-slots.v1"))
            let lockFile = try #require(log.firstIndex(of: "remove vault-slots.lock"))
            #expect(encryptedFile < lockFile)
            if journalFails {
                let plainStore = try #require(log.firstIndex(of: "remove vault-primary.sqlite"))
                #expect(plainStore < encryptedFile)
            }
            try await harness.expectErased()
        }
    }

    /// A writer that had stalled can put the encrypted file back after the erase first removed it, if the erase
    /// couldn't take the lock then. The erase checks again, holding the lock, before it finishes.
    @Test
    func erase_removesAnEncryptedFileAStalledWriterPutBack() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
            let before = try harness.encryptedFileBytes()
            let eraser = harness.makeEraser(whileReloadingWidgets: {
                try? before.write(to: directory.appending(path: EncryptedVaultFile.fileName))
            })

            try await eraser.erase()

            try await harness.expectErased()
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
            let harness = try VaultEraseHarness(directory: directory, session: VaultStoreSession(target: .plain(store)))
            try await harness.seedDevice()

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
            let harness = try VaultEraseHarness(directory: directory)
            try harness.defaults.set("kept", for: VaultEraseHarness.unrelatedSetting)

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

            async let first = eraser.erase()
            async let second = eraser.erase()
            let (firstStore, secondStore) = try await (first, second)

            #expect(firstStore === secondStore)
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
                "remove the wrap stamp",
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

                var failed = false
                do {
                    try await harness.erase()
                } catch {
                    failed = true
                }

                let context = Comment(rawValue: "failing at step \(step), \(steps.names[step - 1])")
                #expect(try !harness.fileNames().contains(EncryptedVaultFile.fileName), context)
                if failed {
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
                    for key in VaultIdentifiers.SecureStorageKey.allCases {
                        #expect(await harness.isStored(key), "\(key), \(context.rawValue)")
                    }
                }
            }
        }
    }

    /// The journal can't be written, perhaps because the disk is full, so the erase removes the vault first to free
    /// space, and then the app stops before the journal's in place. With no journal and no vault, the next launch still
    /// finishes the erase, rather than leave a device in the password mode with nothing to open.
    @Test
    func erase_failingToJournalThenCrashing_isStillFinishedByTheNextLaunch() async throws {
        let steps = try await Self.stepsOfAnErase()
        // Each step of writing the first journal, up to its rename.
        for failStep in 2 ... steps.journalRename {
            // Every step through removing the vault and renaming the second journal into place, and one more.
            for crashStep in failStep + 1 ... failStep + 16 {
                try await withTemporaryDirectory { directory in
                    let harness = try await VaultEraseHarness.encryptedDevice(in: directory)
                    let before = try harness.encryptedFileBytes()
                    harness.fileSystem.inject(.failThenCrash(failAtStep: failStep, crashAtStep: crashStep))

                    _ = try? await harness.erase()
                    let vaultWasRemoved = try !harness.fileNames().contains(EncryptedVaultFile.fileName)
                    let outcome = try await harness.relaunch()

                    let context = Comment(rawValue: "failing at step \(failStep), then crashing at step \(crashStep)")
                    if vaultWasRemoved {
                        #expect(outcome != .password, context)
                        try await harness.expectErased(context)
                    } else {
                        #expect(outcome == .password, context)
                        #expect(try harness.encryptedFileBytes() == before, context)
                    }
                }
            }
        }
    }
}

// MARK: - Harness

/// A device to erase: its storage directory, keychain, count of wrong attempts, the app's defaults and temporary
/// directory, and a store session.
///
/// Every file operation, keychain removal and plain store creation an erase makes is a step of `fileSystem`, which
/// can make it fail or crash. Hooks are recorded in its log too, in order with the steps.
@MainActor
struct VaultEraseHarness {
    static let hookEntries: Set = [
        "release the plain store",
        "clear QuickType",
        "reload widgets",
        "forget the vault's settings",
    ]
    /// Keychain items an erase keeps on purpose, and why. There are none: every item belongs to a vault, or shows one
    /// existed. Every other `SecureStorageKey` must be gone after an erase.
    static let keptKeychainItems: [VaultIdentifiers.SecureStorageKey: String] = [:]
    /// The vault's settings still kept in the app's defaults, which an erase clears.
    static let vaultSettingsKeys = [
        VaultIdentifiers.Backup.lastBackupEvent,
        VaultIdentifiers.AutoBackup.configuration,
        VaultIdentifiers.Preferences.PDF.userHint,
    ]
    /// A setting that isn't the vault's, which an erase keeps.
    static let unrelatedSetting = Key<String>("vault.test.unrelated-setting")
    /// Text from the vault that must be in no file once it's erased.
    static let plaintextMarkers = ["Bank", plaintext].map { Data($0.utf8) }
    /// What the plain store's leftover files, the rehash files and the temp files hold.
    static let plaintext = "ERASED-VAULT-PLAINTEXT"
    /// The app's temporary directory, inside the vault's directory so it's deleted with it.
    static let temporaryDirectoryName = "tmp"

    let directory: URL
    let fileSystem: FaultInjectingSlotFileSystem
    let keychain: FaultInjectingSecureStorage
    let attemptStorage: FaultInjectingAttemptStorage
    let wrapStamps: FaultInjectingWrapStampStorage
    let userDefaults: UserDefaults
    let defaults: Defaults
    let session: VaultStoreSession

    init(directory: URL, session: VaultStoreSession = VaultStoreSession(target: .locked)) throws {
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: LiveSlotFileSystem())
        self.directory = directory
        self.fileSystem = fileSystem
        keychain = FaultInjectingSecureStorage(faults: fileSystem)
        attemptStorage = FaultInjectingAttemptStorage(faults: fileSystem)
        wrapStamps = FaultInjectingWrapStampStorage(faults: fileSystem)
        userDefaults = try testUserDefaults()
        defaults = Defaults(userDefaults: userDefaults)
        self.session = session
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    var temporaryDirectory: URL {
        directory.appending(path: Self.temporaryDirectoryName)
    }

    /// A device with an encrypted vault, as a conversion leaves it, with its session unlocked on it, and everything
    /// else an erase removes (`seedDevice()`), and:
    ///
    /// - the plain store's files, an archive and pending rehash files, as if deleting them after the conversion had
    ///   been interrupted, with the journal still saying so;
    /// - temp files left by crashes while writing the encrypted file and the storage state.
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

        let harness = try VaultEraseHarness(directory: directory, session: conversion.session)
        try await harness.seedDevice()
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
        let harness = try VaultEraseHarness(directory: directory, session: VaultStoreSession(target: .unlocked(store)))
        try await harness.seedDevice()
        return harness
    }

    /// Puts everything an erase clears outside the vault's directory on the device: every keychain item, including ten
    /// wrong attempts in a row, the vault's settings, and a backup PDF left in the temporary directory. And a setting
    /// an erase keeps.
    func seedDevice() async throws {
        for key in VaultIdentifiers.SecureStorageKey.allCases {
            switch key {
            case .backupPassword, .backupPasswordMetadata, .killphraseKey, .searchPassphraseKey:
                await keychain.store(data: Data(key.rawValue.utf8), forKey: key.rawValue)
            case .appLockPasswordAttempts:
                attemptStorage.setCount(AppLockPasswordAttemptCounter.eraseThreshold)
            case .vaultWrapStamp:
                try wrapStamps.save(1_790_000_000_000)
            }
        }
        try defaults.set(
            VaultBackupEvent(
                backupDate: Date(timeIntervalSince1970: 100),
                eventDate: Date(timeIntervalSince1970: 200),
                kind: .exportedToPDF,
                payloadHash: .init(value: Data(repeating: 0xAB, count: 32)),
            ),
            for: Key<VaultBackupEvent>(VaultIdentifiers.Backup.lastBackupEvent),
        )
        try defaults.set(
            AutoBackupConfiguration(
                isEnabled: true,
                retentionDays: .days30,
                providerID: "icloud-drive",
                providerConfigs: ["icloud-drive": Data("folder".utf8)],
                lastBackupHash: "abc",
                lastBackupDate: Date(timeIntervalSince1970: 200),
            ),
            for: Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration),
        )
        try defaults.set("My old hint", for: Key<String>(VaultIdentifiers.Preferences.PDF.userHint))
        try defaults.set("kept", for: Self.unrelatedSetting)
        _ = try BackupPDFTemporaryFiles(fileManager: .default, directory: temporaryDirectory).write(anyGeneratedPDF())
    }

    /// An eraser, as the app makes one.
    ///
    /// - Parameter whileReloadingWidgets: Runs as the widgets reload, after the vault is first removed.
    func makeEraser(whileReloadingWidgets: @escaping @Sendable () -> Void = {}) -> VaultEraser {
        let fileSystem = fileSystem
        let directory = directory
        return VaultEraser(
            directory: directory,
            fileSystem: fileSystem,
            session: session,
            secureStorage: keychain,
            attemptCounter: AppLockPasswordAttemptCounter(storage: attemptStorage, clock: FakeAppLockClock()),
            wrapStamps: wrapStamps,
            defaults: defaults,
            temporaryDirectory: temporaryDirectory,
            hooks: VaultEraser.Hooks(
                releasePlainStore: { fileSystem.record("release the plain store") },
                clearCredentialIdentities: { fileSystem.record("clear QuickType") },
                reloadWidgets: {
                    fileSystem.record("reload widgets")
                    whileReloadingWidgets()
                },
                forgetVaultSettings: { fileSystem.record("forget the vault's settings") },
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

    /// Whether the keychain item is there, wherever it's kept.
    func isStored(_ key: VaultIdentifiers.SecureStorageKey) async -> Bool {
        switch key {
        case .backupPassword, .backupPasswordMetadata, .killphraseKey, .searchPassphraseKey:
            await keychain.keys().contains(key.rawValue)
        case .appLockPasswordAttempts:
            attemptStorage.hasRecord
        case .vaultWrapStamp:
            wrapStamps.hasStamp
        }
    }

    var stateFile: VaultStorageStateFile {
        VaultStorageStateFile(directory: directory, fileSystem: LiveSlotFileSystem())
    }

    /// The files in the vault's directory, apart from the temporary directory.
    func fileNames() throws -> Set<String> {
        try VaultStorageRecoveryTests.fileNames(in: directory).subtracting([Self.temporaryDirectoryName])
    }

    func encryptedFileBytes() throws -> Data {
        try Data(contentsOf: directory.appending(path: EncryptedVaultFile.fileName))
    }

    /// Only a fresh, empty plain store is left: no other file, nothing of the old vault in it, no keychain item, no
    /// count of attempts, none of the vault's settings, no backup PDF, and nothing underway.
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

        for key in VaultIdentifiers.SecureStorageKey.allCases {
            let kept = Self.keptKeychainItems[key] != nil
            #expect(await isStored(key) == kept, "\(key)", sourceLocation: sourceLocation)
        }
        for key in Self.vaultSettingsKeys {
            #expect(userDefaults.object(forKey: key) == nil, "\(key)", sourceLocation: sourceLocation)
        }
        #expect(defaults.get(for: Self.unrelatedSetting) == "kept", context, sourceLocation: sourceLocation)
        let temporaryFiles = try FileManager.default.contentsOfDirectory(
            atPath: temporaryDirectory.path(percentEncoded: false),
        )
        #expect(temporaryFiles.isEmpty, context, sourceLocation: sourceLocation)
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
        switch VaultIdentifiers.SecureStorageKey(rawValue: key) {
        case .killphraseKey: "the killphrase key"
        case .searchPassphraseKey: "the search passphrase key"
        case .backupPassword: "the backup password"
        case .backupPasswordMetadata: "the backup password's record"
        case .appLockPasswordAttempts, .vaultWrapStamp, nil: key
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

/// The wrap stamp in memory, whose removal is a step of a `FaultInjectingSlotFileSystem`.
final class FaultInjectingWrapStampStorage: VaultWrapStampStorage {
    private let stamp = SharedMutex<UInt64?>(nil)
    private let faults: FaultInjectingSlotFileSystem

    init(faults: FaultInjectingSlotFileSystem) {
        self.faults = faults
    }

    var hasStamp: Bool {
        stamp.get { $0 != nil }
    }

    func load() throws -> UInt64? {
        stamp.get { $0 }
    }

    func save(_ newStamp: UInt64) throws {
        stamp.modify { $0 = newStamp }
    }

    func remove() throws {
        try faults.step("remove the wrap stamp")
        stamp.modify { $0 = nil }
    }
}
