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
        persistence.observe(sut)

        let tag = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let hotpCode = VaultItem.Payload.otpCode(anyOTPAuthCode(type: .hotp()))
        let id = try await sut.insert(item: uniqueVaultItem(item: hotpCode, tags: [tag]).makeWritable())
        try await sut.incrementCounter(id: id)
        try await sut.deleteTag(id: tag)
        try await sut.delete(id: id)

        let saves = persistence.saves
        #expect(saves.count == 5)
        // While each save was underway, the store still showed the state before it.
        #expect(saves.map(\.publishedWhileSaving) == [.empty] + saves.dropLast().map(\.state))
        #expect(await sut.state == .empty)
    }

    @Test
    func aChangeThatChangesNothing_savesNothing() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)

        try await sut.delete(id: .new())
        try await sut.deleteTag(id: .init(id: UUID()))
        try await sut.deleteVault()
        _ = await sut.deleteItems(matchingKillphrase: "nothing", using: testDigester)

        #expect(persistence.saves.isEmpty)
    }

    @Test
    func changes_takeTurnsSoEachStartsFromTheOneBefore() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        persistence.holdNextSave()

        let first = Task { try await sut.insert(item: uniqueVaultItem().makeWritable()) }
        await persistence.waitUntilHolding()
        let second = Task { try await sut.insert(item: uniqueVaultItem().makeWritable()) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(persistence.saves.count == 1)
        persistence.release()
        let ids = try await [first.value, second.value].map(\.rawValue)

        #expect(persistence.saves.map { $0.state.items.map(\.id) } == [[ids[0]], ids])
    }

    @Test
    func failedSave_throwsAndLeavesTheStateUnchanged() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        let before = await sut.state
        persistence.script(.failure(TestError()))

        await #expect(throws: TestError.self) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(await sut.state == before)
    }

    @Test
    func conflictingSave_makesTheChangeAgainOnTopOfWhatTheOtherWriterSaved() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        let otherWriters = try Self.state(with: uniqueVaultItem())
        persistence.script(.success(.conflict(saved: otherWriters)))

        let id = try await sut.insert(item: uniqueVaultItem().makeWritable())

        #expect(persistence.saves.count == 2)
        #expect(await sut.state.items.map(\.id) == otherWriters.items.map(\.id) + [id.rawValue])
        #expect(await sut.state == persistence.saves.last?.state)
    }

    @Test
    func conflictingEverySave_throwsAfterThreeTriesHoldingWhatWasSaved() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        let otherWriters = try (0 ..< 3).map { _ in try Self.state(with: uniqueVaultItem()) }
        persistence.script(otherWriters.map { .success(.conflict(saved: $0)) })

        await #expect(throws: EncryptedVaultStoreError.conflict) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(persistence.saves.count == RecordVaultStore.conflictAttempts)
        #expect(await sut.state == otherWriters.last)
    }

    /// The update was made from the item at counter 5. Meanwhile another writer advanced it to 6.
    @Test
    func update_afterAConflict_keepsTheCounterAnotherWriterAdvanced() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .hotp(counter: 5))))
        try await sut.importAndOverrideVault(payload: .init(userDescription: "", items: [item], tags: []))
        var advanced = await sut.state
        advanced.items[0].otpDetails?.counter = 6
        persistence.script(.success(.conflict(saved: advanced)))

        let edited = uniqueVaultItem(id: item.id, item: item.item, userDescription: "Edited")
        try await sut.update(id: item.id, item: edited.makeWritable())

        #expect(await sut.state.items.map(\.otpDetails?.counter) == [6])
        #expect(await sut.state.items.map(\.userDescription) == ["Edited"])
    }

    /// An update that sets the counter itself keeps its own counter.
    @Test
    func update_afterAConflict_keepsACounterTheUpdateChanged() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .hotp(counter: 5))))
        try await sut.importAndOverrideVault(payload: .init(userDescription: "", items: [item], tags: []))
        var advanced = await sut.state
        advanced.items[0].otpDetails?.counter = 6
        persistence.script(.success(.conflict(saved: advanced)))

        let edited = uniqueVaultItem(id: item.id, item: .otpCode(anyOTPAuthCode(type: .hotp(counter: 2))))
        try await sut.update(id: item.id, item: edited.makeWritable())

        #expect(await sut.state.items.map(\.otpDetails?.counter) == [2])
    }

    @Test
    func deleteItemsMatchingKillphrase_returnsFalseWhenTheSaveFails() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        let matching = uniqueVaultItem(killphrase: "red")
        try await sut.importAndOverrideVault(payload: .init(userDescription: "", items: [matching], tags: []))
        let before = await sut.state
        persistence.script(.failure(TestError()))

        let didDelete = await sut.deleteItems(matchingKillphrase: "red", using: testDigester)

        #expect(!didDelete)
        #expect(await sut.state == before)
    }

    /// Another writer saved first, adding an item: the phrase is matched again on top of that, and still deletes.
    @Test
    func deleteItemsMatchingKillphrase_afterAConflict_matchesAgainAndDeletes() async throws {
        let persistence = ScriptedPersistence()
        let sut = RecordVaultStore(persistence: persistence)
        let matching = uniqueVaultItem(killphrase: "red")
        let other = uniqueVaultItem()
        try await sut.importAndOverrideVault(payload: .init(userDescription: "", items: [matching], tags: []))
        try persistence.script(.success(.conflict(saved: Self.state(with: matching, other))))

        let didDelete = await sut.deleteItems(matchingKillphrase: "red", using: testDigester)

        #expect(didDelete)
        #expect(await sut.state.items.map(\.id) == [other.id.rawValue])
    }
}

// MARK: - Helpers

extension RecordVaultStoreTests {
    /// An item holding a decrypted recovery phrase, which no store may write.
    private func plaintextRecoveryPhrase() -> VaultItem {
        VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))
    }

    private struct TestError: Error {}

    private static func state(with items: VaultItem...) throws -> VaultRecordState {
        let encoder = PersistedVaultItemEncoder()
        return try VaultRecordState(
            items: items
                .map { try encoder.encode(item: $0.makeWritable(), writeUpdateContext: $0.makeImportingContext()) },
            tags: [],
        )
    }

    /// Records every state it's asked to save, gives the outcomes it's scripted to, and can hold a save underway.
    private final class ScriptedPersistence: VaultRecordPersistence {
        struct Save: Sendable {
            /// The state to save.
            var state: VaultRecordState
            /// What the store showed while the save was underway, if it's being observed.
            var publishedWhileSaving: VaultRecordState
        }

        private struct State {
            var saves = [Save]()
            var outcomes = [Result<VaultRecordSaveOutcome, any Error>]()
            var store: RecordVaultStore?
            var holdsNextSave = false
            var held: CheckedContinuation<Void, Never>?
        }

        private let state = SharedMutex(State())

        /// Every state saved, or attempted, in order.
        var saves: [Save] {
            state.get { $0.saves }
        }

        /// What the next saves give, in order. Saves after them succeed.
        func script(_ outcomes: Result<VaultRecordSaveOutcome, any Error>...) {
            script(outcomes)
        }

        func script(_ outcomes: [Result<VaultRecordSaveOutcome, any Error>]) {
            state.modify { $0.outcomes = outcomes }
        }

        /// Notes what `store` shows while each save is underway.
        func observe(_ store: RecordVaultStore) {
            state.modify { $0.store = store }
        }

        func holdNextSave() {
            state.modify { $0.holdsNextSave = true }
        }

        func release() {
            state.modify { state in
                state.held?.resume()
                state.held = nil
            }
        }

        /// Waits (for up to 5 seconds) until a save is being held.
        func waitUntilHolding() async {
            let deadline = ContinuousClock.now + .seconds(5)
            while state.get({ $0.held == nil }), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }

        func save(_ newState: VaultRecordState) async throws -> VaultRecordSaveOutcome {
            let published = await state.get { $0.store }?.state
            let holds = state.modify { state in
                state.saves.append(Save(state: newState, publishedWhileSaving: published ?? .empty))
                defer { state.holdsNextSave = false }
                return state.holdsNextSave
            }
            if holds {
                await withCheckedContinuation { continuation in
                    state.modify { $0.held = continuation }
                }
            }
            let outcome = state.modify { state in
                state.outcomes.isEmpty ? .success(.saved) : state.outcomes.removeFirst()
            }
            return try outcome.get()
        }
    }
}
