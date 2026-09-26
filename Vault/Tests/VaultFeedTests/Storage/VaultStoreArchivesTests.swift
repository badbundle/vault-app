import Foundation
import Testing
@testable import VaultFeed

/// Vaults set aside because they couldn't be opened may hold the only copy of some items, so they're only ever
/// deleted on purpose.
struct VaultStoreArchivesTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "archives-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test
    func archives_listsOnlySetAsideVaults() throws {
        defer { removeDirectory() }
        let archive = try makeArchive(named: "vault-primary.failed-open-2026-09-01T10-00-00Z")
        try Data("not an archive".utf8).write(to: directory.appending(path: "vault-primary.sqlite"))
        try FileManager.default.createDirectory(
            at: directory.appending(path: "some-other-folder"),
            withIntermediateDirectories: true,
        )

        let archives = makeSUT().archives()

        #expect(archives.map(\.url.lastPathComponent) == [archive.lastPathComponent])
    }

    @Test
    func archives_areOldestFirst() throws {
        defer { removeDirectory() }
        let older = try makeArchive(named: "vault-primary.failed-open-a", date: Date(timeIntervalSince1970: 1000))
        let newer = try makeArchive(named: "vault-primary.failed-open-b", date: Date(timeIntervalSince1970: 2000))

        let archives = makeSUT().archives()

        #expect(archives.map(\.url.lastPathComponent) == [older.lastPathComponent, newer.lastPathComponent])
        #expect(archives.map(\.date) == [Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 2000)])
    }

    /// An empty folder has nothing in it to lose.
    @Test
    func archives_removesEmptyArchiveFolders() throws {
        defer { removeDirectory() }
        let empty = directory.appending(path: "vault-primary.failed-open-empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let archives = makeSUT().archives()

        #expect(archives.isEmpty)
        #expect(FileManager.default.fileExists(atPath: empty.path(percentEncoded: false)) == false)
    }

    @Test
    func deleteAll_deletesEverySetAsideVaultAndNothingElse() throws {
        defer { removeDirectory() }
        let first = try makeArchive(named: "vault-primary.failed-open-a")
        let second = try makeArchive(named: "vault-primary.failed-open-b")
        let liveStore = directory.appending(path: "vault-primary.sqlite")
        try Data("live".utf8).write(to: liveStore)
        let sut = makeSUT()

        try sut.deleteAll()

        #expect(sut.archives().isEmpty)
        #expect(FileManager.default.fileExists(atPath: first.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: second.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: liveStore.path(percentEncoded: false)))
    }

    /// The store's recovery and the list agree on where set-aside vaults go.
    @Test
    func archives_includesStoreSetAsideByRecovery() throws {
        defer { removeDirectory() }
        try Data("not a sqlite store".utf8).write(to: directory.appending(path: "vault-primary.sqlite"))

        _ = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()

        let archives = makeSUT().archives()
        #expect(archives.count == 1)
        let archived = try FileManager.default.contentsOfDirectory(
            atPath: #require(archives.first).url.path(percentEncoded: false),
        )
        #expect(archived.contains("vault-primary.sqlite"))
    }

    // MARK: - Deleting all data

    @Test
    func deleteVault_deletesSetAsideVaultsAndPendingRehashFiles() async throws {
        defer { removeDirectory() }
        let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
        let archive = try makeArchive(named: "vault-primary.failed-open-a")
        let pendingKillphrases = PendingKillphraseRehashStore.defaultURL(storeDirectory: directory)
        let pendingSearchPassphrases = PendingSearchPassphraseRehashStore.defaultURL(storeDirectory: directory)
        try PendingKillphraseRehashStore(fileURL: pendingKillphrases).write([.init(itemID: UUID(), phrase: "a")])
        try PendingSearchPassphraseRehashStore(fileURL: pendingSearchPassphrases)
            .write([.init(itemID: UUID(), phrase: "b")])

        try await store.deleteVault()

        #expect(FileManager.default.fileExists(atPath: archive.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: pendingKillphrases.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: pendingSearchPassphrases.path(percentEncoded: false)) == false)
    }

    /// Replacing the vault with an import isn't deleting all data: a set-aside vault may hold items the import
    /// doesn't.
    @Test
    func importAndOverride_keepsSetAsideVaults() async throws {
        defer { removeDirectory() }
        let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
        let archive = try makeArchive(named: "vault-primary.failed-open-a")

        try await store.importAndOverrideVault(payload: .init(userDescription: "", items: [], tags: []))

        #expect(FileManager.default.fileExists(atPath: archive.path(percentEncoded: false)))
    }
}

// MARK: - Helpers

extension VaultStoreArchivesTests {
    private func makeSUT() -> PersistedLocalVaultStoreArchives {
        PersistedLocalVaultStoreArchives(storageDirectory: directory)
    }

    private func makeArchive(named name: String, date: Date? = nil) throws -> URL {
        let url = directory.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("archived store".utf8).write(to: url.appending(path: "vault-primary.sqlite"))
        if let date {
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: url.path(percentEncoded: false))
        }
        return url
    }

    private func removeDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }
}
