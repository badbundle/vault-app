import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// Behavior of the record store beyond the contract every store shares (`VaultStoreContractTests`).
struct RecordVaultStoreTests {
    @Test
    func init_servesTheGivenState() async throws {
        let item = uniqueVaultItem()
        let record = try PersistedVaultItemEncoder().encode(
            item: item.makeWritable(),
            writeUpdateContext: item.makeImportingContext(),
        )
        let sut = RecordVaultStore(state: VaultRecordState(items: [record], tags: []))

        let result = try await sut.retrieve(query: .init())

        #expect(result.items == [item])
    }

    @Test
    func state_keepsItemsInTheOrderTheyWereFirstStored() async throws {
        let sut = RecordVaultStore()
        let first = try await sut.insert(item: uniqueVaultItem().makeWritable())
        let second = try await sut.insert(item: uniqueVaultItem().makeWritable())
        let third = try await sut.insert(item: uniqueVaultItem().makeWritable())

        try await sut.update(id: second, item: uniqueVaultItem(userDescription: "Updated").makeWritable())

        #expect(await sut.state.items.map(\.id) == [first.rawValue, second.rawValue, third.rawValue])
    }

    @Test
    func insert_failureLeavesTheStateUnchanged() async throws {
        let sut = RecordVaultStore()
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        let before = await sut.state

        await #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try await sut.insert(item: plaintextRecoveryPhrase().makeWritable())
        }

        #expect(await sut.state == before)
    }

    @Test
    func importAndMergeVault_failureLeavesTheStateUnchanged() async throws {
        let sut = RecordVaultStore()
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        let before = await sut.state
        let payload = VaultApplicationPayload(
            userDescription: "",
            items: [uniqueVaultItem(), plaintextRecoveryPhrase()],
            tags: [anyVaultItemTag()],
        )

        await #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try await sut.importAndMergeVault(payload: payload)
        }

        #expect(await sut.state == before)
    }

    @Test
    func importAndOverrideVault_failureLeavesTheStateUnchanged() async throws {
        let sut = RecordVaultStore()
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        let before = await sut.state
        let payload = VaultApplicationPayload(
            userDescription: "",
            items: [uniqueVaultItem(), plaintextRecoveryPhrase()],
            tags: [anyVaultItemTag()],
        )

        await #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try await sut.importAndOverrideVault(payload: payload)
        }

        #expect(await sut.state == before)
    }

    @Test
    func importAndMergeVault_throwsWithoutChangesWhenAStoredItemDoesNotDecode() async throws {
        let sut = RecordVaultStore()
        let id = try await sut.insert(item: uniqueVaultItem().makeWritable())
        try await sut.corruptItemAlgorithm(id: id)
        let before = await sut.state
        let payload = VaultApplicationPayload(userDescription: "", items: [uniqueVaultItem()], tags: [])

        await #expect(throws: (any Error).self) {
            try await sut.importAndMergeVault(payload: payload)
        }

        #expect(await sut.state == before)
    }

    @Test
    func deleteItemsMatchingKillphrase_leavesItemsWithoutAMatchUntouched() async throws {
        let sut = RecordVaultStore()
        let matching = uniqueVaultItem(killphrase: "red")
        let other = uniqueVaultItem(killphrase: "blue")
        let none = uniqueVaultItem(killphrase: nil)
        try await sut.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [matching, other, none],
            tags: [],
        ))

        let didDelete = await sut.deleteItems(matchingKillphrase: "red", using: testDigester)

        #expect(didDelete)
        #expect(await sut.state.items.map(\.id) == [other.id.rawValue, none.id.rawValue])
    }
}

// MARK: - Persistence

extension RecordVaultStoreTests {
    @Test
    func everyChange_isSavedBeforeItsPublished() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)

        let tag = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let id = try await sut.insert(item: uniqueVaultItem(tags: [tag]).makeWritable())
        try await sut.incrementCounter(id: id)
        try await sut.deleteTag(id: tag)
        try await sut.delete(id: id)

        let saved = persistence.saved
        #expect(saved.count == 5)
        #expect(saved.last == .empty)
        #expect(await sut.state == .empty)
    }

    @Test
    func failedSave_throwsAndLeavesTheStateUnchanged() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        let before = await sut.state
        persistence.nextOutcome = .failure(TestError())

        await #expect(throws: TestError.self) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(await sut.state == before)
    }

    @Test
    func conflictingSave_throwsAndTakesWhatTheOtherWriterSaved() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        let otherWriters = try VaultRecordState(
            items: [PersistedVaultItemEncoder().encode(item: uniqueVaultItem().makeWritable())],
            tags: [],
        )
        persistence.nextOutcome = .success(.conflict(saved: otherWriters))

        await #expect(throws: EncryptedVaultStoreError.conflict) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(await sut.state == otherWriters)
    }

    @Test
    func deleteItemsMatchingKillphrase_returnsFalseWhenTheSaveFails() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        let matching = uniqueVaultItem(killphrase: "red")
        try await sut.importAndOverrideVault(payload: .init(userDescription: "", items: [matching], tags: []))
        let before = await sut.state
        persistence.nextOutcome = .failure(TestError())

        let didDelete = await sut.deleteItems(matchingKillphrase: "red", using: testDigester)

        #expect(!didDelete)
        #expect(await sut.state == before)
    }

    @Test
    func deleteItemsMatchingKillphrase_returnsFalseOnAConflict() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        let matching = uniqueVaultItem(killphrase: "red")
        try await sut.importAndOverrideVault(payload: .init(userDescription: "", items: [matching], tags: []))
        let otherWriters = await sut.state
        persistence.nextOutcome = .success(.conflict(saved: otherWriters))

        let didDelete = await sut.deleteItems(matchingKillphrase: "red", using: testDigester)

        #expect(!didDelete)
        #expect(await sut.state == otherWriters)
    }
}

// MARK: - Helpers

extension RecordVaultStoreTests {
    /// An item holding a decrypted recovery phrase, which no store may write.
    private func plaintextRecoveryPhrase() -> VaultItem {
        VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))
    }

    private struct TestError: Error {}

    /// Records every state it's asked to save, and gives the outcome it's told to for the next one.
    private final class ScriptedPersistence: VaultRecordPersistence {
        private let log = SharedMutex([VaultRecordState]())
        private let outcome = SharedMutex(Result<VaultRecordSaveOutcome, any Error>.success(.saved))

        /// Every state saved, or attempted, in order.
        var saved: [VaultRecordState] {
            log.value
        }

        /// What the next save gives. Later saves succeed.
        var nextOutcome: Result<VaultRecordSaveOutcome, any Error> {
            get { outcome.value }
            set { outcome.modify { $0 = newValue } }
        }

        func save(_ state: VaultRecordState) throws -> VaultRecordSaveOutcome {
            log.modify { $0.append(state) }
            let result = outcome.modify { outcome in
                defer { outcome = .success(.saved) }
                return outcome
            }
            return try result.get()
        }
    }
}
