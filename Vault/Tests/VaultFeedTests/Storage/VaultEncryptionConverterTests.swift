import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// Converting the plain store into an encrypted vault, on disk. See also `VaultStorageRecoveryTests`.
struct VaultEncryptionConverterTests {
    private let password = PlainVaultConversionHarness.password
}

// MARK: - Converting

extension VaultEncryptionConverterTests {
    @Test
    func encrypt_copiesEveryRecordAndSwitchesTheSessionToTheVault() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            let before = try await Self.seed(harness.store)

            try await harness.encrypt()

            let vault = try #require(try await harness.openEncryptedVault())
            #expect(vault.state.items == before.items)
            #expect(vault.state.tags == before.tags)
            #expect(try await harness.session.retrieve(query: .init()).errors.count == 1)
            #expect(try await harness.session.retrieveTags().count == before.tags.count)
            #expect(try !harness.plainStoreFilesExist())
            #expect(try harness.stateFile.read() == VaultStorageState(
                mode: .password,
                unlockDeadline: PlainVaultConversionHarness.unlockDeadline,
            ))
        }
    }

    @Test
    func encrypt_putsTheVaultInARandomSlotWithTenDuressSlots() async throws {
        var realSlots = Set<Int>()
        for _ in 0 ..< 12 {
            try await withTemporaryDirectory { directory in
                let harness = try PlainVaultConversionHarness(directory: directory)
                try await harness.encrypt()

                let vault = try #require(try await harness.openEncryptedVault())
                let duressSlots = vault.state.vault.duressSlots
                #expect(duressSlots.count == 10)
                #expect(Set(duressSlots).count == 10)
                #expect(!duressSlots.contains(vault.slot))
                #expect(duressSlots.allSatisfy(VaultSlotFile.slotIndices.contains))
                realSlots.insert(vault.slot)
            }
        }
        // Twelve conversions all landing in one slot would happen with odds of 1 in 16^11.
        #expect(realSlots.count > 1)
    }

    @Test
    func encrypt_resetsTheAttemptCountFirstThenClearsQuickTypeAndReloadsWidgets() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            harness.attemptStorage.setRecord(count: 3, latestAt: .now)

            try await harness.encrypt()

            #expect(harness.log.value == [
                "reset the count",
                "release the plain store",
                "clear QuickType",
                "reload widgets",
            ])
        }
    }

    /// Unlocking the new vault as the lock screen will, with its deadline from the storage state.
    @Test
    func encrypt_leavesAVaultTheUnlockServiceOpens() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            let before = try await Self.seed(harness.store)
            try await harness.encrypt()
            let session = VaultStoreSession(target: .locked)
            let service = VaultUnlockService(
                file: EncryptedVaultFile(directory: directory),
                session: session,
                attemptCounter: AppLockPasswordAttemptCounter(
                    storage: LoggingAttemptStorage(log: SharedMutex([])),
                    clock: FakeAppLockClock(),
                ),
                deadlineStore: harness.stateFile,
                purgeVaultContents: {},
                wrapStamper: .inMemory(),
            )

            #expect(try await service.unlock(password: "wrong") == .wrongPassword)
            #expect(try await service.unlock(password: password) == .unlocked)

            let retrieved = try await session.retrieve(query: .init())
            #expect(retrieved.items.count + retrieved.errors.count == before.items.count)
        }
    }
}

// MARK: - Preconditions

extension VaultEncryptionConverterTests {
    @Test
    func encrypt_whenThePlainStoreDidNotOpenNormally_refuses() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory, openedNormally: false)

            await #expect(throws: VaultEncryptionError.plainStoreDidNotOpen) {
                try await harness.encrypt()
            }

            try await Self.expectUntouched(harness)
        }
    }

    @Test
    func encrypt_withPhrasesStillToRehash_refuses() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            try PendingKillphraseRehashStore(
                fileURL: PendingKillphraseRehashStore.defaultURL(storeDirectory: directory),
            ).write([.init(itemID: UUID(), phrase: "kill me")])

            await #expect(throws: VaultEncryptionError.pendingRehashes) {
                try await harness.encrypt()
            }

            try await Self.expectUntouched(harness)
        }
    }

    @Test
    func encrypt_withArchives_refusesUntilTheUserAgreesToDeleteThem() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            let archive = try Self.makeArchive(in: directory)

            await #expect(throws: VaultEncryptionError.archivesNeedDeleting) {
                try await harness.encrypt(deletingArchives: false)
            }
            try await Self.expectUntouched(harness)

            try await harness.encrypt(deletingArchives: true)
            #expect(try !harness.fileNames().contains(archive.lastPathComponent))
        }
    }

    @Test
    func encrypt_ofAVaultTooLargeForTheLargestSlot_refuses() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            // Base64 of random bytes only compresses to about three quarters, so this doesn't fit a 4 MiB slot.
            let contents = SlotRandom.bytes(count: 4_500_000).base64EncodedString()
            try await harness.store.insert(
                item: uniqueVaultItem(item: .secureNote(anySecureNote(contents: contents))).makeWritable(),
            )

            await #expect(throws: VaultEncryptionError.vaultTooLarge) {
                try await harness.encrypt()
            }

            try await Self.expectUntouched(harness)
        }
    }

    @Test
    func encrypt_whenAlreadyEncrypted_refuses() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            try await harness.encrypt()
            let bytes = try Data(contentsOf: directory.appending(path: EncryptedVaultFile.fileName))

            await #expect(throws: VaultEncryptionError.alreadyEncrypted) {
                try await harness.encrypt()
            }

            #expect(try Data(contentsOf: directory.appending(path: EncryptedVaultFile.fileName)) == bytes)
        }
    }
}

// MARK: - Failures and crashes

extension VaultEncryptionConverterTests {
    /// Every step of a conversion.
    private struct Steps {
        var names: [String]
        /// Renaming the committing state into place, the commit point: a failure or crash up to here leaves the
        /// plain store as the vault, and from here the encrypted one.
        var commitRename: Int

        /// Flushing the directory never fails a step: by then the rename it follows has happened.
        func isFatal(_ step: Int) -> Bool {
            names[step - 1] != "flush directory"
        }
    }

    private static func stepsOfAConversion() async throws -> Steps {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            try await Self.seed(harness.store)
            try await harness.encrypt()
            let names = harness.fileSystem.log.filter { $0 != "unlock" }
            let stateRenames = names.indices.filter { names[$0] == "rename state temp to vault-storage-state.json" }
            return try Steps(names: names, commitRename: #require(stateRenames.dropFirst().first) + 1)
        }
    }

    /// A conversion that fails at any step before it commits leaves the plain store as the vault, with nothing else
    /// on disk. One that fails after it has committed still finishes, and the next launch deletes what it couldn't.
    @Test
    func encrypt_failingAtAnyStep_leavesThePlainVaultOrTheEncryptedOne() async throws {
        let steps = try await Self.stepsOfAConversion()
        for step in 1 ... steps.names.count {
            try await withTemporaryDirectory { directory in
                let harness = try PlainVaultConversionHarness(directory: directory)
                let before = try await Self.seed(harness.store)
                harness.fileSystem.inject(.fail(atStep: step))

                let result = await Result(asyncThrowingClosure: { try await harness.encrypt() })

                let context = Comment(rawValue: "failing at step \(step), \(steps.names[step - 1])")
                let staysPlain = step <= steps.commitRename && steps.isFatal(step)
                if staysPlain {
                    #expect(throws: (any Error).self, context) { try result.get() }
                    #expect(await !harness.session.isLocked, context)
                    #expect(try !harness.fileNames().contains(EncryptedVaultFile.fileName), context)
                } else {
                    #expect(throws: Never.self, context) { try result.get() }
                }
                try await Self.expectRelaunch(harness, as: staysPlain ? .plain : .password, with: before, context)
            }
        }
    }

    /// The app stops at any step. The next launch finds the plain vault if the conversion hadn't committed, or the
    /// encrypted one if it had: never both, never neither, and nothing left over.
    @Test
    func encrypt_crashingAtAnyStep_leavesThePlainVaultOrTheEncryptedOneForTheNextLaunch() async throws {
        let steps = try await Self.stepsOfAConversion()
        for step in 1 ... steps.names.count {
            try await withTemporaryDirectory { directory in
                let harness = try PlainVaultConversionHarness(directory: directory)
                let before = try await Self.seed(harness.store)
                harness.fileSystem.inject(.crash(atStep: step))

                _ = try? await harness.encrypt()

                let context = Comment(rawValue: "crashing at step \(step), \(steps.names[step - 1])")
                let expectedMode: VaultStorageState.Mode = step <= steps.commitRename ? .plain : .password
                try await Self.expectRelaunch(harness, as: expectedMode, with: before, context)
            }
        }
    }

    /// A step fails before the commit, and then undoing it fails too, at any of the next few steps. The plain store
    /// is still the vault: at once, or once the next launch has finished the undoing.
    @Test
    func encrypt_failingAndThenFailingToUndo_keepsThePlainVault() async throws {
        let steps = try await Self.stepsOfAConversion()
        for step in 1 ... steps.commitRename where steps.isFatal(step) {
            for later in step + 1 ... step + 4 {
                try await withTemporaryDirectory { directory in
                    let harness = try PlainVaultConversionHarness(directory: directory)
                    let before = try await Self.seed(harness.store)
                    harness.fileSystem.inject(.fail(atSteps: [step, later]))

                    await #expect(throws: (any Error).self) { try await harness.encrypt() }

                    let context = Comment(rawValue: "failing at steps \(step) and \(later), \(steps.names[step - 1])")
                    // The session only goes back to the plain store if the journal shows the conversion didn't
                    // commit: otherwise it stays locked. It's never the encrypted vault.
                    if await !harness.session.isLocked {
                        #expect(try await harness.session.retrieve(query: .init()).errors.count == 1, context)
                    }
                    try await Self.expectRelaunch(harness, as: .plain, with: before, context)
                }
            }
        }
    }

    /// A step fails before the commit, and the app stops while it's undoing it.
    @Test
    func encrypt_failingAndThenCrashingWhileUndoing_keepsThePlainVault() async throws {
        let steps = try await Self.stepsOfAConversion()
        for step in 1 ... steps.commitRename where steps.isFatal(step) {
            for later in step + 1 ... step + 4 {
                try await withTemporaryDirectory { directory in
                    let harness = try PlainVaultConversionHarness(directory: directory)
                    let before = try await Self.seed(harness.store)
                    harness.fileSystem.inject(.failThenCrash(failAtStep: step, crashAtStep: later))

                    _ = try? await harness.encrypt()

                    let context =
                        Comment(rawValue: "failing at \(step), crashing at \(later), \(steps.names[step - 1])")
                    try await Self.expectRelaunch(harness, as: .plain, with: before, context)
                }
            }
        }
    }

    @Test
    func encrypt_calledAgainWhileConverting_isRefusedAndChangesNothing() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory)
            let before = try await Self.seed(harness.store)

            async let first = Result(asyncThrowingClosure: { try await harness.encrypt() })
            async let second = Result(asyncThrowingClosure: { try await harness.encrypt() })
            let results = await [first, second]

            let failures = results.compactMap { result -> VaultEncryptionError? in
                if case let .failure(error) = result {
                    error as? VaultEncryptionError
                } else {
                    nil
                }
            }
            #expect(failures == [.alreadyEncrypted])
            #expect(await !harness.session.isLocked)
            let vault = try #require(try await harness.openEncryptedVault())
            #expect(vault.state.items == before.items)
        }
    }

    /// For example, the app went to the background, and locked, while converting.
    @Test
    func encrypt_whenTheSessionLocksMeanwhile_leavesItLocked() async throws {
        try await withTemporaryDirectory { directory in
            let harness = try PlainVaultConversionHarness(directory: directory, releasingPlainStore: { session in
                await session.lock()
            })

            try await harness.encrypt()

            #expect(await harness.session.isLocked)
            #expect(try await harness.openEncryptedVault() != nil)
        }
    }

    /// The QuickType identity store and the widgets are cleared while the journal still says so, so a launch after
    /// a crash does it again.
    @Test
    func encrypt_clearsTheSystemSurfacesWhileTheJournalStillSaysTo() async throws {
        try await withTemporaryDirectory { directory in
            let journalWhileClearing = SharedMutex<VaultStorageState.Transition?>(nil)
            let stateFile = VaultStorageStateFile(directory: directory)
            let harness = try PlainVaultConversionHarness(
                directory: directory,
                clearingCredentialIdentities: {
                    journalWhileClearing.modify { $0 = try? stateFile.read().transition }
                },
            )

            try await harness.encrypt()

            #expect(journalWhileClearing.value == .clearingSystemSurfaces)
            #expect(try stateFile.read().transition == nil)
        }
    }
}

// MARK: - Helpers

extension VaultEncryptionConverterTests {
    /// Fills the store with a tag, items that carry it, a killphrase and a search passphrase, and an item that
    /// doesn't decode.
    @discardableResult
    static func seed(_ store: PersistedLocalVaultStore) async throws -> VaultRecordState {
        let tag = try await store.insertTag(item: anyVaultItemTag(name: "Work").makeWritable())
        try await store.insert(item: uniqueVaultItem(userDescription: "Bank", tags: [tag]).makeWritable())
        try await store.insert(item: uniqueVaultItem(killphrase: "kill me").makeWritable())
        try await store.insert(
            item: uniqueVaultItem(item: .secureNote(anySecureNote(title: "Note", contents: "Contents")))
                .makeWritable(),
        )
        let broken = try await store.insert(item: uniqueVaultItem().makeWritable())
        try await store.corruptItemAlgorithm(id: broken)
        return try await store.recordState()
    }

    /// A folder like the ones the plain store's recovery sets aside, holding a copy of its database.
    static func makeArchive(in directory: URL) throws -> URL {
        let archive = directory.appending(path: PersistedLocalVaultStoreArchives.directoryNamePrefix + "2026-09-26")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("plaintext".utf8).write(to: archive.appending(path: "vault-primary.sqlite"))
        return archive
    }

    /// The plain store is still the vault, open in the session, with no state file or encrypted file.
    static func expectUntouched(
        _ harness: PlainVaultConversionHarness,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        let names = try harness.fileNames()
        #expect(!names.contains(VaultStorageStateFile.fileName), sourceLocation: sourceLocation)
        #expect(!names.contains(EncryptedVaultFile.fileName), sourceLocation: sourceLocation)
        #expect(try harness.plainStoreFilesExist(), sourceLocation: sourceLocation)
        #expect(await !harness.session.isLocked, sourceLocation: sourceLocation)
    }

    /// Launches again, and requires the vault to be in `mode` with exactly the records it had, and nothing left of
    /// the other mode or any temp file.
    static func expectRelaunch(
        _ harness: PlainVaultConversionHarness,
        as mode: VaultStorageState.Mode,
        with before: VaultRecordState,
        _ context: Comment,
    ) async throws {
        let relaunched = try await harness.relaunch()
        #expect(relaunched.mode == mode, context)
        #expect(relaunched.state.items == before.items, context)
        #expect(relaunched.state.tags == before.tags, context)
        try expectNoLeftovers(harness, mode: relaunched.mode, context)
    }

    /// Whichever way the vault ended up, nothing of the other way, or any temp file, is left.
    static func expectNoLeftovers(
        _ harness: PlainVaultConversionHarness,
        mode: VaultStorageState.Mode,
        _ context: Comment,
    ) throws {
        let names = try harness.fileNames()
        #expect(!names.contains { $0.hasPrefix(EncryptedVaultFile.temporaryFilePrefix) }, context)
        #expect(!names.contains { $0.hasPrefix(VaultStorageStateFile.temporaryFilePrefix) }, context)
        switch mode {
        case .plain:
            #expect(!names.contains(EncryptedVaultFile.fileName), context)
            #expect(!names.contains(VaultStorageStateFile.fileName), context)
        case .password:
            #expect(try !harness.plainStoreFilesExist(), context)
            #expect(try harness.stateFile.read().transition == nil, context)
        }
    }
}
