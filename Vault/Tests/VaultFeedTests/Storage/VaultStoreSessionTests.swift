import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

struct VaultStoreSessionTests {
    // MARK: - Plain

    @Test
    func plain_forwardsReads() async throws {
        let item = uniqueVaultItem()
        let tag = anyVaultItemTag()
        let store = GatedVaultStore(items: [item], tags: [tag])
        let sut = VaultStoreSession(target: .plain(store))

        let retrieved = try await sut.retrieve(query: .init())
        let hasAnyItems = try await sut.hasAnyItems
        let tags = try await sut.retrieveTags()
        let export = try await sut.exportVault(userDescription: "description")

        #expect(retrieved.items == [item])
        #expect(hasAnyItems)
        #expect(tags == [tag])
        #expect(export.items == [item])
        #expect(export.tags == [tag])
        #expect(export.userDescription == "description")
        #expect(await store.calls == ["retrieve", "hasAnyItems", "retrieveTags", "exportVault"])
    }

    @Test
    func plain_forwardsWrites() async throws {
        let store = GatedVaultStore()
        let sut = VaultStoreSession(target: .plain(store))
        let item = uniqueVaultItem()

        try await performEveryWrite(on: sut, item: item)

        #expect(await store.calls == Self.everyWrite)
    }

    @Test(arguments: [true, false])
    func plain_forwardsKillphraseDeletion(storeDeletes: Bool) async {
        let store = GatedVaultStore(killphraseDeletes: storeDeletes)
        let sut = VaultStoreSession(target: .plain(store))

        let deleted = await sut.deleteItems(matchingKillphrase: "phrase", using: anyKillphraseMatcher())

        #expect(deleted == storeDeletes)
        #expect(await store.calls == ["deleteItems"])
    }

    @Test
    func plain_isNotLocked() async {
        let sut = VaultStoreSession(target: .plain(GatedVaultStore()))

        #expect(await !sut.isLocked)
    }

    // MARK: - Locked

    @Test
    func locked_isLocked() async {
        let sut = VaultStoreSession(target: .locked)

        #expect(await sut.isLocked)
    }

    @Test
    func locked_readsFindNothing() async throws {
        let sut = VaultStoreSession(target: .locked)

        let retrieved = try await sut.retrieve(query: .init())
        let hasAnyItems = try await sut.hasAnyItems
        let tags = try await sut.retrieveTags()

        #expect(retrieved.items.isEmpty)
        #expect(retrieved.errors.isEmpty)
        #expect(!hasAnyItems)
        #expect(tags.isEmpty)
    }

    @Test
    func locked_exportThrows() async {
        // Never an empty export that a backup could replace a real one with.
        let sut = VaultStoreSession(target: .locked)

        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.exportVault(userDescription: "")
        }
    }

    @Test
    func locked_everyWriteThrows() async {
        let sut = VaultStoreSession(target: .locked)
        let item = uniqueVaultItem()
        let tagID = Identifier<VaultItemTag>.new()
        let payload = VaultApplicationPayload(userDescription: "", items: [], tags: [])

        await #expect(throws: VaultStoreSessionError.locked) { try await sut.insert(item: item.makeWritable()) }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.update(id: item.id, item: item.makeWritable())
        }
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.delete(id: item.id) }
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.incrementCounter(id: item.id) }
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.reorder(items: [item.id], to: .start) }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.updateTag(id: tagID, item: anyVaultItemTag().makeWritable())
        }
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.deleteTag(id: tagID) }
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.importAndMergeVault(payload: payload) }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.importAndOverrideVault(payload: payload)
        }
        await #expect(throws: VaultStoreSessionError.locked) { try await sut.deleteVault() }
    }

    @Test
    func locked_killphraseDeletionFindsNothing() async {
        // Indistinguishable from a phrase that matches nothing (MANIFESTO C2).
        let sut = VaultStoreSession(target: .locked)

        let deleted = await sut.deleteItems(matchingKillphrase: "phrase", using: anyKillphraseMatcher())

        #expect(!deleted)
    }

    // MARK: - Switching

    @Test
    func lock_stopsReachingTheStore() async throws {
        let store = GatedVaultStore(items: [uniqueVaultItem()], tags: [anyVaultItemTag()], killphraseDeletes: true)
        let sut = VaultStoreSession(target: .plain(store))

        await sut.lock()
        _ = try await sut.retrieve(query: .init())
        _ = try await sut.hasAnyItems
        _ = try await sut.retrieveTags()
        _ = try? await sut.exportVault(userDescription: "")
        try? await performEveryWrite(on: sut, item: uniqueVaultItem())
        _ = await sut.deleteItems(matchingKillphrase: "phrase", using: anyKillphraseMatcher())

        #expect(await sut.isLocked)
        #expect(await store.calls.isEmpty)
    }

    @Test
    func switchTo_forwardsToTheNewStore() async throws {
        let first = GatedVaultStore(items: [uniqueVaultItem()])
        let secondItem = uniqueVaultItem()
        let second = GatedVaultStore(items: [secondItem])
        let sut = VaultStoreSession(target: .plain(first))

        await sut.lock()
        await sut.switchTo(.plain(second))
        let retrieved = try await sut.retrieve(query: .init())

        #expect(retrieved.items == [secondItem])
        #expect(await first.calls.isEmpty)
        #expect(await second.calls == ["retrieve"])
        #expect(await !sut.isLocked)
    }

    @Test
    func lock_nothingUnderway_returnsAtOnce() async {
        let sut = VaultStoreSession(target: .plain(GatedVaultStore()))

        await sut.lock()

        #expect(await sut.isLocked)
    }

    @Test
    func lock_waitsForACallAlreadyUnderway() async throws {
        let store = GatedVaultStore()
        await store.hold()
        let sut = VaultStoreSession(target: .plain(store))
        let write = Task { try await sut.insert(item: uniqueVaultItem().makeWritable()) }
        await store.waitUntilHolding()

        let lockFinished = Flag()
        let locking = Task {
            await sut.lock()
            await lockFinished.set()
        }
        try await Task.sleep(for: .milliseconds(50))

        // Locked for anything new at once, but not done until the write has finished with the store.
        #expect(await sut.isLocked)
        #expect(try await sut.retrieve(query: .init()).items.isEmpty)
        #expect(await !lockFinished.isSet)
        #expect(await store.calls == ["insert"])

        await store.release()
        _ = try await write.value
        await locking.value

        #expect(await lockFinished.isSet)
    }

    @Test
    func lock_waitsForEveryCallUnderway() async throws {
        let store = GatedVaultStore()
        await store.hold()
        let sut = VaultStoreSession(target: .plain(store))
        let first = Task { try await sut.retrieve(query: .init()) }
        let second = Task { try await sut.delete(id: .new()) }
        await store.waitUntilHolding(2)

        let lockFinished = Flag()
        let locking = Task {
            await sut.lock()
            await lockFinished.set()
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await !lockFinished.isSet)

        await store.release()
        _ = try await first.value
        try await second.value
        await locking.value

        #expect(await lockFinished.isSet)
    }
}

// MARK: - Helpers

extension VaultStoreSessionTests {
    private static let everyWrite = [
        "insert", "update", "delete", "incrementCounter", "reorder",
        "insertTag", "updateTag", "deleteTag",
        "importAndMergeVault", "importAndOverrideVault", "deleteVault",
    ]

    private func performEveryWrite(on sut: VaultStoreSession, item: VaultItem) async throws {
        let tag = anyVaultItemTag()
        let payload = VaultApplicationPayload(userDescription: "", items: [], tags: [])
        try await sut.insert(item: item.makeWritable())
        try await sut.update(id: item.id, item: item.makeWritable())
        try await sut.delete(id: item.id)
        try await sut.incrementCounter(id: item.id)
        try await sut.reorder(items: [item.id], to: .start)
        try await sut.insertTag(item: tag.makeWritable())
        try await sut.updateTag(id: tag.id, item: tag.makeWritable())
        try await sut.deleteTag(id: tag.id)
        try await sut.importAndMergeVault(payload: payload)
        try await sut.importAndOverrideVault(payload: payload)
        try await sut.deleteVault()
    }

    private func anyKillphraseMatcher() -> KillphraseDigester {
        KillphraseDigester(key: .zero())
    }
}

private actor Flag {
    private(set) var isSet = false

    func set() {
        isSet = true
    }
}
