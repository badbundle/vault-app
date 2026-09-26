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

// MARK: - Helpers

extension RecordVaultStoreTests {
    /// An item holding a decrypted recovery phrase, which no store may write.
    private func plaintextRecoveryPhrase() -> VaultItem {
        VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))
    }
}
