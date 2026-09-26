import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import VaultFeed

/// The plain store as an extension sees it, while the app might be converting it.
struct GuardedPlainVaultStoreTests {
    @Test
    func whilePlain_readsAndWritesThePlainStore() async throws {
        let (sut, store, _) = try makeSUT()

        let id = try await sut.insert(item: uniqueVaultItem().makeWritable())

        #expect(try await sut.retrieve(query: .init()).items.map(\.id) == [id])
        #expect(try await store.retrieve(query: .init()).items.map(\.id) == [id])
    }

    @Test(arguments: [
        VaultStorageState(mode: .plain, transition: .encrypting),
        VaultStorageState(mode: .password, transition: .deletingPlainStore(archives: [])),
        VaultStorageState(mode: .password),
    ])
    func onceNotPlain_readsNothingAndWritesNothing(state: VaultStorageState) async throws {
        let (sut, store, stateFile) = try makeSUT()
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .hotp(counter: 5))), killphrase: "red")
        try await store.importAndOverrideVault(payload: .init(userDescription: "", items: [item], tags: []))
        try stateFile.write(state)

        #expect(try await sut.retrieve(query: .init()) == .empty())
        #expect(try await sut.retrieveTags() == [])
        #expect(try await !sut.hasAnyItems)
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.incrementCounter(id: item.id)
        }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }
        #expect(await !sut.deleteItems(matchingKillphrase: "red", using: testDigester))
        #expect(try await store.retrieve(query: .init()).items == [item])
    }

    /// A write that started while the vault was plain waits for a conversion holding the lock, then finds the
    /// conversion underway and writes nothing: a counter advanced then would be lost from the snapshot.
    @Test
    func writeThatWaitsForAConversion_checksAgainAndWritesNothing() async throws {
        let (sut, store, stateFile) = try makeSUT()
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .hotp(counter: 5))))
        try await store.importAndOverrideVault(payload: .init(userDescription: "", items: [item], tags: []))
        let conversion = try await EncryptedVaultFile(
            directory: EncryptedVaultFixture.inMemoryDirectory,
            fileSystem: stateFile.fileSystem,
        ).lockUntilReleased()

        let increment = Task { try await sut.incrementCounter(id: item.id) }
        try await Task.sleep(for: .milliseconds(50))
        try stateFile.write(VaultStorageState(mode: .plain, transition: .encrypting))
        conversion.release()

        await #expect(throws: VaultStoreSessionError.locked) {
            try await increment.value
        }
        #expect(try await store.retrieve(query: .init()).items == [item])
    }

    private func makeSUT() throws -> (GuardedPlainVaultStore, PersistedLocalVaultStore, VaultStorageStateFile) {
        let store = try PersistedLocalVaultStore.inMemory()
        let fileSystem = InMemorySlotFileSystem()
        let directory = EncryptedVaultFixture.inMemoryDirectory
        let sut = GuardedPlainVaultStore(store: store, directory: directory, fileSystem: fileSystem)
        return (sut, store, VaultStorageStateFile(directory: directory, fileSystem: fileSystem))
    }
}
