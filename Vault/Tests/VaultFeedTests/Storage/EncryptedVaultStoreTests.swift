import CryptoKit
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// Behavior of the encrypted store beyond the contract every store shares (`VaultStoreContractTests`): saving to
/// the file, failures at every step, and other writers.
struct EncryptedVaultStoreTests {
    /// The steps of a save, in order: `EncryptedVaultFile` and `SlotFilePersistence`.
    static let stepsOfASave = [
        "lock vault-slots.lock",
        "read vault-slots.v1",
        "list directory",
        "create temp",
        "flush temp",
        "read temp",
        "rename temp to vault-slots.v1",
        "flush directory",
    ]

    /// The last step before the file holds the change.
    static let renameStep = 7

    // MARK: Opening

    @Test
    func init_readsTheVaultInItsSlot() async throws {
        let tag = anyVaultItemTag()
        let item = uniqueVaultItem(tags: [tag.id])
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [item], tags: [tag]))

        let sut = try await fixture.openStore()

        #expect(try await sut.retrieve(query: .init()).items == [item])
        #expect(try await sut.retrieveTags() == [tag])
    }

    @Test
    func init_refusesAVaultSavedByANewerVersion() async throws {
        let fixture = try EncryptedVaultFixture(payloadVersion: EncryptedVaultPayload.currentVersion + 1)

        await #expect(throws: EncryptedVaultStoreError.unsupportedPayloadVersion(2)) {
            try await fixture.openStore()
        }
    }

    @Test
    func open_removesTemporaryFilesACrashLeftBehind() async throws {
        let fileSystem = InMemorySlotFileSystem()
        let fixture = try EncryptedVaultFixture(fileSystem: fileSystem)
        let stray = fixture.file.directory.appending(path: EncryptedVaultFile.temporaryFilePrefix + "stray")
        try fileSystem.createFile(at: stray, contents: fixture.bytes())

        _ = try await fixture.openStore()

        #expect(try fixture.temporaryFileNames().isEmpty)
    }

    @Test
    func open_findsNothingWithoutAFile() async throws {
        let file = EncryptedVaultFile(
            directory: EncryptedVaultFixture.inMemoryDirectory,
            fileSystem: InMemorySlotFileSystem(),
        )

        #expect(try await file.open() == nil)
    }
}

// MARK: - Saving

extension EncryptedVaultStoreTests {
    @Test
    func everyChange_isSavedToTheFile() async throws {
        let fixture = try EncryptedVaultFixture()
        let sut = try await fixture.openStore()

        let tag = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        #expect(try await fixture.savedState() == sut.records.state)
        let id = try await sut.insert(item: uniqueVaultItem(tags: [tag]).makeWritable())
        #expect(try await fixture.savedState() == sut.records.state)
        try await sut.update(id: id, item: uniqueVaultItem(userDescription: "Updated").makeWritable())
        #expect(try await fixture.savedState() == sut.records.state)
        try await sut.deleteTag(id: tag)
        #expect(try await fixture.savedState() == sut.records.state)
        try await sut.deleteVault()
        #expect(try fixture.savedState() == .empty)
    }

    @Test
    func save_sealsTheSlotAtTheNextGenerationAndCopiesEveryOtherSlot() async throws {
        let fixture = try EncryptedVaultFixture()
        let before = try VaultSlotFile(bytes: fixture.bytes())
        let firstGeneration = try fixture.savedSlot().generation
        let sut = try await fixture.openStore()

        try await sut.insert(item: uniqueVaultItem().makeWritable())
        try await sut.insert(item: uniqueVaultItem().makeWritable())

        let after = try VaultSlotFile(bytes: fixture.bytes())
        #expect(after.header == before.header)
        for index in VaultSlotFile.slotIndices where index != fixture.slotIndex {
            #expect(after.bytes[after.slotRange(index)] == before.bytes[before.slotRange(index)], "slot \(index)")
        }
        #expect(try fixture.savedSlot().generation == firstGeneration + 2)
    }

    @Test
    func save_takesEveryStepHoldingTheLock() async throws {
        let fixture = try EncryptedVaultFixture()
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let sut = try await fixture.through(fileSystem).openStore()
        let opening = fileSystem.log.count

        try await sut.insert(item: uniqueVaultItem().makeWritable())

        #expect(Array(fileSystem.log.dropFirst(opening)) == Self.stepsOfASave + ["unlock"])
    }

    @Test
    func save_growsTheFileWhenTheVaultOutgrowsItsSlot() async throws {
        let fixture = try EncryptedVaultFixture(slotIndex: 3)
        let otherState = try Self.state(items: [uniqueVaultItem()])
        let other = try await fixture.addingVault(inSlot: 9, state: otherState)
        let sut = try await fixture.openStore()
        // Base64 of random bytes only compresses to about three quarters, so this doesn't fit a 1 MiB slot.
        let contents = SlotRandom.bytes(count: 1_500_000).base64EncodedString()

        try await sut.insert(item: uniqueVaultItem(item: .secureNote(anySecureNote(contents: contents))).makeWritable())

        #expect(try fixture.bytes().count == 128 + 16 * 2 * (1 << 20))
        #expect(try await fixture.savedState() == sut.records.state)
        #expect(try other.savedState() == otherState)
    }
}

// MARK: - Failures

extension EncryptedVaultStoreTests {
    @Test(arguments: 1 ... EncryptedVaultStoreTests.renameStep)
    func save_failingAtAnyStepUpToTheRename_leavesTheFileAndTheStoreAsTheyWere(step: Int) async throws {
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [uniqueVaultItem()]))
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let sut = try await fixture.through(fileSystem).openStore()
        let bytesBefore = try fixture.bytes()
        let stateBefore = await sut.records.state

        fileSystem.inject(.fail(atStep: step))
        await #expect(throws: (any Error).self, "failing at \(Self.stepsOfASave[step - 1])") {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(try fixture.bytes() == bytesBefore)
        #expect(await sut.records.state == stateBefore)
        #expect(try fixture.temporaryFileNames().isEmpty)
        // The lock was released, unless taking it was the step that failed.
        #expect(fileSystem.log.last == (step == 1 ? Self.stepsOfASave[0] : "unlock"))
        // Nothing was left half done: the next change saves.
        fileSystem.inject(nil)
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        #expect(try await fixture.savedState() == sut.records.state)
    }

    /// Once the rename has happened the file holds the change, so it's published even if flushing the directory
    /// fails.
    @Test
    func save_failingToFlushTheDirectory_stillSaves() async throws {
        let fixture = try EncryptedVaultFixture()
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let sut = try await fixture.through(fileSystem).openStore()

        fileSystem.inject(.fail(atStep: Self.stepsOfASave.count))
        let id = try await sut.insert(item: uniqueVaultItem().makeWritable())

        #expect(await sut.records.state.items.map(\.id) == [id.rawValue])
        #expect(try await fixture.savedState() == sut.records.state)
    }

    /// After a crash at any step, the next launch finds the vault as it was before the change, or with the change
    /// if the rename happened. It never finds anything else, and the temp file is gone.
    @Test(arguments: 1 ... EncryptedVaultStoreTests.stepsOfASave.count)
    func save_crashingAtAnyStep_leavesTheOldOrNewVaultForTheNextLaunch(step: Int) async throws {
        let before = try Self.state(items: [uniqueVaultItem()])
        let fixture = try EncryptedVaultFixture(state: before)
        let firstGeneration = try fixture.savedSlot().generation
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let sut = try await fixture.through(fileSystem).openStore()

        fileSystem.inject(.crash(atStep: step))
        _ = try? await sut.insert(item: uniqueVaultItem().makeWritable())
        let relaunched = try await fixture.openStore()

        let after = await relaunched.records.state
        if step <= Self.renameStep {
            #expect(after == before)
        } else {
            #expect(after.items.count == 2)
            #expect(after.items.first == before.items.first)
        }
        #expect(try fixture.savedSlot().generation == firstGeneration + (step <= Self.renameStep ? 0 : 1))
        #expect(try fixture.temporaryFileNames().isEmpty)
    }

    @Test
    func save_whoseFileDoesNotReadBackAsWritten_isNotUsed() async throws {
        let fixture = try EncryptedVaultFixture()
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let sut = try await fixture.through(fileSystem).openStore()
        let bytesBefore = try fixture.bytes()

        fileSystem.inject(.corruptReadBack)
        await #expect(throws: EncryptedVaultStoreError.verificationFailed) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(try fixture.bytes() == bytesBefore)
        #expect(await sut.records.state == .empty)
        #expect(try fixture.temporaryFileNames().isEmpty)
    }

    /// A killphrase whose deletion couldn't be saved reads as one that matched nothing (MANIFESTO C2), and the item
    /// stays, in memory and in the file.
    @Test(arguments: 1 ... EncryptedVaultStoreTests.renameStep)
    func deleteItemsMatchingKillphrase_returnsFalseWhenTheSaveFails(step: Int) async throws {
        let item = uniqueVaultItem(killphrase: "red")
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [item]))
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let sut = try await fixture.through(fileSystem).openStore()

        fileSystem.inject(.fail(atStep: step))
        let didDelete = await sut.deleteItems(matchingKillphrase: "red", using: testDigester)

        #expect(!didDelete)
        #expect(try await sut.retrieve(query: .init()).items == [item])
        #expect(try fixture.savedState().items.map(\.id) == [item.id.rawValue])
    }

    @Test
    func save_withoutAFile_throwsFileMissing() async throws {
        let fileSystem = InMemorySlotFileSystem()
        let fixture = try EncryptedVaultFixture(fileSystem: fileSystem)
        let sut = try await fixture.openStore()
        fileSystem.setContents(nil, at: fixture.file.url)

        await #expect(throws: EncryptedVaultStoreError.fileMissing) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }
        #expect(await sut.records.state == .empty)
    }
}

extension EncryptedVaultStoreTests {
    /// A writer killed mid-save, AutoFill say, leaves a temp file: a whole copy of the file, whose items the right
    /// password still opens. The next save removes it before anything else, so an item deleted then leaves no copy
    /// behind (MANIFESTO C6).
    @Test
    func save_firstRemovesATempFileAnotherWriterLeftBehind() async throws {
        let fileSystem = InMemorySlotFileSystem()
        let item = uniqueVaultItem(killphrase: "red")
        let fixture = try EncryptedVaultFixture(fileSystem: fileSystem, state: Self.state(items: [item]))
        let sut = try await fixture.openStore()
        let stray = fixture.file.directory.appending(path: EncryptedVaultFile.temporaryFilePrefix + "autofill")
        try fileSystem.createFile(at: stray, contents: fixture.bytes())

        #expect(await sut.deleteItems(matchingKillphrase: "red", using: testDigester))

        #expect(try fixture.temporaryFileNames().isEmpty)
        #expect(try fixture.savedState().items.isEmpty)
    }

    /// Here the rename fails, and then so does removing the temp file.
    @Test
    func save_thatCantRemoveItsOwnTempFile_leavesItForTheNextSaveToRemove() async throws {
        let fixture = try EncryptedVaultFixture()
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let sut = try await fixture.through(fileSystem).openStore()

        fileSystem.inject(.fail(atSteps: [Self.renameStep, Self.renameStep + 1]))
        await #expect(throws: FaultInjectingSlotFileSystem.InjectedFault.self) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }
        #expect(try fixture.temporaryFileNames().count == 1)

        fileSystem.inject(nil)
        try await sut.insert(item: uniqueVaultItem().makeWritable())

        #expect(try fixture.temporaryFileNames().isEmpty)
        #expect(try await fixture.savedState() == sut.records.state)
    }

    @Test
    func save_ofAVaultTooLargeForTheLargestSlot_throwsAndChangesNothing() async throws {
        let fixture = try EncryptedVaultFixture()
        let sut = try await fixture.openStore()
        let bytesBefore = try fixture.bytes()
        // Base64 of random bytes compresses to about three quarters: more than a 4 MiB slot holds.
        let contents = SlotRandom.bytes(count: 4_500_000).base64EncodedString()

        await #expect(throws: VaultSlotFileError.payloadTooLarge) {
            try await sut
                .insert(item: uniqueVaultItem(item: .secureNote(anySecureNote(contents: contents))).makeWritable())
        }

        #expect(try fixture.bytes() == bytesBefore)
        #expect(await sut.records.state == .empty)
    }
}

// MARK: - Other writers

extension EncryptedVaultStoreTests {
    /// Two stores on one vault stand in for the app and its AutoFill extension. A store that finds the other saved
    /// first makes its change again on top of what the other saved.
    @Test
    func twoStoresOnOneVault_makeAConflictingChangeOnTopOfTheOtherAndLoseNeither() async throws {
        try await withTemporaryDirectory { directory in
            let fixture = try EncryptedVaultFixture(fileSystem: LiveSlotFileSystem(), directory: directory)
            let app = try await fixture.openStore()
            let autoFill = try await fixture.openStore()

            let first = try await app.insert(item: uniqueVaultItem().makeWritable())
            let second = try await autoFill.insert(item: uniqueVaultItem().makeWritable())

            #expect(try fixture.savedState().items.map(\.id) == [first.rawValue, second.rawValue])
            #expect(try await fixture.savedState() == autoFill.records.state)
            try await app.delete(id: first)
            #expect(try fixture.savedState().items.map(\.id) == [second.rawValue])
            #expect(try await fixture.savedState() == app.records.state)
        }
    }

    /// An update made on top of another writer's change to the same item wins, as the last save does in the SQLite
    /// store.
    @Test
    func update_onTopOfAnotherWritersChangeToTheSameItem_winsLikeTheLastSave() async throws {
        let item = uniqueVaultItem(userDescription: "Original")
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [item]))
        let app = try await fixture.openStore()
        let autoFill = try await fixture.openStore()

        try await autoFill.update(id: item.id, item: uniqueVaultItem(userDescription: "AutoFill").makeWritable())
        try await app.update(id: item.id, item: uniqueVaultItem(userDescription: "App").makeWritable())

        #expect(try fixture.savedState().items.map(\.userDescription) == ["App"])
    }

    @Test
    func update_ofAnItemAnotherWriterDeleted_throwsItemNotFound() async throws {
        let item = uniqueVaultItem()
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [item]))
        let app = try await fixture.openStore()
        let autoFill = try await fixture.openStore()
        try await autoFill.delete(id: item.id)

        await #expect(throws: RecordVaultStore.Error.itemNotFound) {
            try await app.update(id: item.id, item: uniqueVaultItem().makeWritable())
        }

        #expect(await app.records.state == .empty)
    }

    @Test
    func twoStoresWritingAtOnce_neverLoseAWrite() async throws {
        try await withTemporaryDirectory { directory in
            let fixture = try EncryptedVaultFixture(fileSystem: LiveSlotFileSystem(), directory: directory)
            let stores = try await [fixture.openStore(), fixture.openStore()]

            let ids = try await withThrowingTaskGroup(of: [UUID].self) { group in
                for store in stores {
                    group.addTask {
                        var ids = [UUID]()
                        for _ in 0 ..< 5 {
                            try await ids.append(Self.insertRetryingConflicts(into: store))
                        }
                        return ids
                    }
                }
                return try await group.reduce(into: []) { $0 += $1 }
            }

            #expect(ids.count == 10)
            #expect(try Set(fixture.savedState().items.map(\.id)) == Set(ids))
        }
    }

    /// For example, AutoFill advanced a HOTP counter just before the killphrase was typed in the app.
    @Test
    func deleteItemsMatchingKillphrase_afterAnotherWritersChange_stillDeletesAndKeepsTheirChange() async throws {
        let item = uniqueVaultItem(killphrase: "red")
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [item]))
        let app = try await fixture.openStore()
        let autoFill = try await fixture.openStore()
        let other = try await autoFill.insert(item: uniqueVaultItem().makeWritable())

        let didDelete = await app.deleteItems(matchingKillphrase: "red", using: testDigester)

        #expect(didDelete)
        #expect(try fixture.savedState().items.map(\.id) == [other.rawValue])
        #expect(try await fixture.savedState() == app.records.state)
    }

    /// A phrase that matches nothing saves nothing, so it doesn't pick up another writer's change either: nothing
    /// about the store changes.
    @Test
    func deleteItemsMatchingKillphrase_matchingNothing_changesNothing() async throws {
        let item = uniqueVaultItem(killphrase: "red")
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [item]))
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let app = try await fixture.through(fileSystem).openStore()
        let stateBefore = await app.records.state
        let steps = fileSystem.log.count

        let didDelete = await app.deleteItems(matchingKillphrase: "blue", using: testDigester)

        #expect(!didDelete)
        #expect(fileSystem.log.count == steps)
        #expect(await app.records.state == stateBefore)
    }

    @Test
    func incrementCounter_onTopOfAnotherWritersIncrement_appliesEachOnce() async throws {
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .hotp(counter: 5))))
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [item]))
        let app = try await fixture.openStore()
        let autoFill = try await fixture.openStore()

        try await autoFill.incrementCounter(id: item.id)
        try await app.incrementCounter(id: item.id)

        #expect(try fixture.savedState().items.map(\.otpDetails?.counter) == [7])
    }

    /// The app saves an edit made before AutoFill used a code. The counter doesn't go back, so that code isn't
    /// generated again.
    @Test
    func update_onTopOfAnotherWritersIncrement_keepsTheAdvancedCounter() async throws {
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .hotp(counter: 5))))
        let fixture = try EncryptedVaultFixture(state: Self.state(items: [item]))
        let app = try await fixture.openStore()
        let autoFill = try await fixture.openStore()
        try await autoFill.incrementCounter(id: item.id)

        let edited = uniqueVaultItem(id: item.id, item: item.item, userDescription: "Edited")
        try await app.update(id: item.id, item: edited.makeWritable())

        let saved = try #require(try fixture.savedState().items.first)
        #expect(saved.userDescription == "Edited")
        #expect(saved.otpDetails?.counter == 6)
    }

    @Test
    func reorder_onTopOfAnotherWritersChange_appliesOnce() async throws {
        let items = (0 ..< 3).map { uniqueVaultItem(relativeOrder: UInt64($0), userDescription: "\($0)") }
        let fixture = try EncryptedVaultFixture(state: Self.state(items: items))
        let app = try await fixture.openStore()
        let autoFill = try await fixture.openStore()
        let tag = try await autoFill.insertTag(item: anyVaultItemTag().makeWritable())

        try await app.reorder(items: [items[2].id], to: .start)

        let saved = try fixture.savedState()
        let ordered = saved.items.sorted { $0.relativeOrder < $1.relativeOrder }
        #expect(ordered.map(\.userDescription) == ["2", "0", "1"])
        #expect(ordered.map(\.relativeOrder) == [0, 1, 2])
        #expect(saved.tags.map(\.id) == [tag.id])
    }

    @Test
    func twoVaultsInOneFile_saveWithoutDisturbingEachOther() async throws {
        let first = try EncryptedVaultFixture(slotIndex: 3)
        let second = try await first.addingVault(inSlot: 9)
        let firstStore = try await first.openStore()
        let secondStore = try await second.openStore()

        for _ in 0 ..< 3 {
            try await firstStore.insert(item: uniqueVaultItem().makeWritable())
            try await secondStore.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(try await first.savedState() == firstStore.records.state)
        #expect(try await second.savedState() == secondStore.records.state)
        #expect(await firstStore.records.state.items.count == 3)
    }

    /// For example, another process changed the password.
    @Test
    func save_afterTheSlotWasRewrapped_throwsSlotLostAndChangesNothing() async throws {
        let fixture = try EncryptedVaultFixture()
        let sut = try await fixture.openStore()
        try await fixture.file.withLock { file in
            var contents = try #require(try file.read())
            let slot = try contents.openSlot(fixture.slotIndex, with: fixture.rootKey)
            try contents.rewrap(slot, with: .password(derivedKey: SymmetricKey(size: .bits256)), wrappedAt: Date())
            try file.write(contents) { _ in }
        }
        let bytesBefore = try fixture.bytes()

        await #expect(throws: EncryptedVaultStoreError.slotLost) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(try fixture.bytes() == bytesBefore)
        #expect(await sut.records.state == .empty)
    }
}

// MARK: - Performance

extension EncryptedVaultStoreTests {
    /// Guards the design's figures (about 9 ms to load and 19 ms to save 1,000 items, optimized, on an M5 Max)
    /// against regressions. A debug build in the simulator takes about 15 ms and 35 ms, so the budgets leave room for
    /// a busy machine. It's skipped under Thread Sanitizer, which slows everything several times over.
    @Test(.disabled(if: isRunningUnderThreadSanitizer, "Thread Sanitizer slows everything down"))
    func thousandItems_loadAndSaveWithinBudget() async throws {
        try await withTemporaryDirectory { directory in
            let fixture = try EncryptedVaultFixture(
                fileSystem: LiveSlotFileSystem(),
                directory: directory,
                state: Self.typicalState(itemCount: 1000),
            )
            let clock = ContinuousClock()
            var loads = [Duration]()
            var saves = [Duration]()

            for _ in 0 ..< 3 {
                let start = clock.now
                let store = try await fixture.openStore()
                _ = try await store.retrieve(query: .init())
                loads.append(clock.now - start)

                let saveStart = clock.now
                try await store.insert(item: uniqueVaultItem().makeWritable())
                saves.append(clock.now - saveStart)
            }

            let load = try #require(loads.min())
            let save = try #require(saves.min())
            #expect(load < .milliseconds(150), "Loading 1,000 items took \(load)")
            #expect(save < .milliseconds(300), "Saving 1,000 items took \(save)")
        }
    }
}

// MARK: - Helpers

extension EncryptedVaultStoreTests {
    static func state(items: [VaultItem], tags: [VaultItemTag] = []) throws -> VaultRecordState {
        let itemEncoder = PersistedVaultItemEncoder()
        let tagEncoder = PersistedVaultTagEncoder()
        return try VaultRecordState(
            items: items.map {
                try itemEncoder.encode(item: $0.makeWritable(), writeUpdateContext: $0.makeImportingContext())
            },
            tags: tags.map { tagEncoder.encode(tag: $0.makeWritable(), writeUpdateContext: $0.makeImportingContext()) },
        )
    }

    /// The design's typical vault: 60% TOTP codes, 30% notes of about 800 characters and 10% password-encrypted
    /// items, with 8 tags and up to 2 on each item.
    static func typicalState(itemCount: Int) throws -> VaultRecordState {
        let tags = (0 ..< 8).map { anyVaultItemTag(name: "Tag \($0)") }
        let note = String(repeating: "A line of a typical secure note, ", count: 25)
        let items = (0 ..< itemCount).map { index in
            let payload: VaultItem.Payload = switch index % 10 {
            case 0 ..< 6: .otpCode(anyOTPAuthCode(accountName: "account\(index)@example.com", issuerName: "Issuer"))
            case 6 ..< 9: .secureNote(anySecureNote(title: "Note \(index)", contents: note))
            default: .encryptedItem(anyEncryptedItem(title: "Encrypted \(index)"))
            }
            let itemTags = Set(tags.shuffled().prefix(index % 3).map(\.id))
            return uniqueVaultItem(item: payload, userDescription: "Item \(index)", tags: itemTags)
        }
        return try state(items: items, tags: tags)
    }

    /// Inserts an item, trying again each time another store saved first.
    private static func insertRetryingConflicts(into store: EncryptedVaultStore) async throws -> UUID {
        while true {
            do {
                return try await store.insert(item: uniqueVaultItem().makeWritable()).rawValue
            } catch EncryptedVaultStoreError.conflict {
                continue
            }
        }
    }
}

/// Whether the tests are running under Thread Sanitizer.
private let isRunningUnderThreadSanitizer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__tsan_init") != nil
