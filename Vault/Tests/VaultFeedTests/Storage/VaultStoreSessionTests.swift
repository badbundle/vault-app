import Foundation
import FoundationExtensions
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

    @Test
    func lock_returnsItsOwnEpoch_evenIfTheSessionLocksAgainWhileItWaits() async throws {
        let store = GatedVaultStore()
        await store.hold()
        let sut = VaultStoreSession(target: .plain(store))
        let write = Task { try await sut.insert(item: uniqueVaultItem().makeWritable()) }
        await store.waitUntilHolding()

        let first = Task { await sut.lock() }
        try await Task.sleep(for: .milliseconds(50))
        let second = Task { await sut.lock() }
        try await Task.sleep(for: .milliseconds(50))
        await store.release()
        _ = try await write.value
        let firstEpoch = await first.value
        let secondEpoch = await second.value

        #expect(firstEpoch == 1)
        #expect(secondEpoch == 2)
        #expect(await !sut.switchTo(.plain(store), unlessLockedSince: firstEpoch))
        #expect(await sut.isLocked)
    }
}

// MARK: - Open vault

extension VaultStoreSessionTests {
    @Test
    func openVault_isTheVaultTheSessionReads() async throws {
        let store = try await EncryptedVaultFixture().openStore()
        let other = try await EncryptedVaultFixture().openStore()
        let plainStore = GatedVaultStore()
        let sut = VaultStoreSession(target: .plain(plainStore))
        let plain = await sut.openVault
        guard case .plain = plain else {
            Issue.record("Expected the plain store open")
            return
        }
        #expect(await sut.openVault.isSame(as: plain))

        await sut.switchTo(.unlocked(store))
        #expect(await sut.openVault.isSame(as: .encrypted(store)))
        #expect(await !sut.openVault.isSame(as: .encrypted(other)))

        await sut.lock()
        // Nothing is the same as no vault: there's nothing whose settings could be written.
        #expect(await !sut.openVault.isSame(as: .locked))
        guard case .locked = await sut.openVault else {
            Issue.record("Expected no vault open")
            return
        }

        // Opening the plain store again, even the same store, is another time it's open.
        await sut.switchTo(.plain(plainStore))
        #expect(await !sut.openVault.isSame(as: plain))
        let reopened = await sut.openVault
        #expect(await sut.openVault.isSame(as: reopened))
    }

    @Test
    func openVaultChanges_yieldsTheVaultOpenAfterEachSwitch() async throws {
        let store = try await EncryptedVaultFixture().openStore()
        let other = try await EncryptedVaultFixture().openStore()
        let sut = VaultStoreSession(target: .plain(GatedVaultStore()))
        let plain = await sut.openVault
        var changes = await sut.openVaultChanges().makeAsyncIterator()

        // The vault open now, first.
        #expect(await changes.next()?.isSame(as: plain) == true)
        await sut.switchTo(.unlocked(store))
        #expect(await changes.next()?.isSame(as: .encrypted(store)) == true)
        await sut.lock()
        let locked = await changes.next()
        guard case .locked = locked else {
            Issue.record("Expected no vault open, got \(String(describing: locked))")
            return
        }
        await sut.switchTo(.unlocked(other))
        #expect(await changes.next()?.isSame(as: .encrypted(other)) == true)
    }

    @Test
    func whileOpen_withTheOpenVault_runs() async throws {
        let store = try await EncryptedVaultFixture().openStore()
        let sut = VaultStoreSession(target: .unlocked(store))

        let result = try await sut.whileOpen(.encrypted(store)) { 42 }

        #expect(result == 42)
    }

    /// Something that read one vault's settings mustn't write them into another.
    @Test
    func whileOpen_afterAnotherVaultOpened_throwsLockedWithoutRunning() async throws {
        let store = try await EncryptedVaultFixture().openStore()
        let other = try await EncryptedVaultFixture().openStore()
        let sut = VaultStoreSession(target: .unlocked(store))
        await sut.switchTo(.unlocked(other))
        let ran = Flag()

        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.whileOpen(.encrypted(store)) { await ran.set() }
        }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.whileOpen(.plain(.init(count: 0))) { await ran.set() }
        }
        #expect(await !ran.isSet)
    }

    /// An erase or a conversion locks the session, then deletes the plain store's settings: something that read them
    /// before mustn't write them back, even once the session has the plain store again.
    @Test
    func whileOpen_forThePlainStoreAsItWasOpenBeforeALock_throwsLockedWithoutRunning() async throws {
        let store = GatedVaultStore()
        let sut = VaultStoreSession(target: .plain(store))
        let plain = await sut.openVault
        let ran = Flag()

        await sut.lock()
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.whileOpen(plain) { await ran.set() }
        }
        await sut.switchTo(.plain(store))
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.whileOpen(plain) { await ran.set() }
        }
        #expect(await !ran.isSet)
        try await sut.whileOpen(sut.openVault) { await ran.set() }
        #expect(await ran.isSet)
    }

    @Test
    func whileOpen_whenLocked_throwsLockedWithoutRunning() async throws {
        let sut = VaultStoreSession(target: .locked)
        let ran = Flag()

        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.whileOpen(.plain(.init(count: 0))) { await ran.set() }
        }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.whileOpen(.locked) { await ran.set() }
        }
        #expect(await !ran.isSet)
    }

    /// Like any other call, it keeps the vault open until it's done: locking waits for it.
    @Test
    func lock_waitsForAWhileOpenUnderway() async throws {
        let store = try await EncryptedVaultFixture().openStore()
        let sut = VaultStoreSession(target: .unlocked(store))
        let started = Pending<Void>.signal()
        let release = Pending<Void>.signal()
        let body = Task {
            try await sut.whileOpen(.encrypted(store)) {
                await started.fulfill()
                try await release.wait()
            }
        }
        try await started.wait()

        let lockFinished = Flag()
        let locking = Task {
            await sut.lock()
            await lockFinished.set()
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await !lockFinished.isSet)

        await release.fulfill()
        try await body.value
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
