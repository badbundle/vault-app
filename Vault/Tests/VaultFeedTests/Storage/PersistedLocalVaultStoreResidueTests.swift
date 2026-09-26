import Foundation
import FoundationExtensions
import SwiftData
import Testing
@testable import VaultFeed

/// Deleted content must not stay in the store's files (MANIFESTO C6): not in the SQLite file, its write-ahead
/// log (`-wal`) or the log's index (`-shm`).
///
/// Each test uses a real store on disk and searches the raw bytes of every file for text that was deleted.
/// Long notes spill onto overflow pages, which SQLite frees whole, so each test deletes both a short and a
/// long one. The tests run against the store as the app opens it and as the contract suite does
/// (`VaultStoreEngine.swiftDataSQLite`).
struct PersistedLocalVaultStoreResidueTests {
    private let killDigester = KillphraseDigester(key: .zero())
    private let searchDigester = SearchPassphraseDigester(key: .zero())

    @Test(arguments: StoreSetup.allCases)
    func killphraseDeletion_leavesNoTraceInStoreFiles(setup: StoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { removeStore(at: storeURL) }
        try await insertDoomedNotes(into: store, killphrase: "kill me")
        let keptID = try await store.insert(item: note(title: "KEPT-TITLE", contents: "KEPT-BODY").makeWritable())
        try expectTraces(of: doomedText, in: storeURL, found: true, "before deleting, the notes should be on disk")

        let didDelete = await store.deleteItems(matchingKillphrase: "kill me", using: killDigester)

        #expect(didDelete)
        try expectTraces(of: doomedText, in: storeURL, found: false)
        let remaining = try await store.retrieve(query: .init()).items.map(\.id)
        #expect(remaining == [keptID])
    }

    @Test(arguments: StoreSetup.allCases)
    func delete_leavesNoTraceInStoreFiles(setup: StoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { removeStore(at: storeURL) }
        let ids = try await insertDoomedNotes(into: store)

        for id in ids {
            try await store.delete(id: id)
        }

        try expectTraces(of: doomedText, in: storeURL, found: false)
    }

    @Test(arguments: StoreSetup.allCases)
    func deleteVault_leavesNoTraceInStoreFiles(setup: StoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { removeStore(at: storeURL) }
        try await insertDoomedNotes(into: store)

        try await store.deleteVault()

        try expectTraces(of: doomedText, in: storeURL, found: false)
    }

    @Test(arguments: StoreSetup.allCases)
    func importAndOverride_leavesNoTraceOfReplacedItems(setup: StoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { removeStore(at: storeURL) }
        try await insertDoomedNotes(into: store)

        try await store.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [note(title: "IMPORTED-TITLE", contents: "IMPORTED-BODY")],
            tags: [],
        ))

        try expectTraces(of: doomedText, in: storeURL, found: false)
        try expectTraces(of: [Data("IMPORTED-BODY".utf8)], in: storeURL, found: true, "the import should be stored")
    }

    @Test(arguments: StoreSetup.allCases)
    func changingKillphrase_leavesNoTraceOfOldDigest(setup: StoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { removeStore(at: storeURL) }
        let oldDigest = killDigester.makeDigest(phrase: "old phrase")
        let item = note(title: "title", contents: "contents", killphrase: oldDigest)
        let id = try await store.insert(item: item.makeWritable())

        var changed = item.makeWritable()
        changed.killphraseUpdate = .set(killDigester.makeDigest(phrase: "new phrase"))
        try await store.update(id: id, item: changed)

        try expectTraces(of: [oldDigest.digest, oldDigest.salt], in: storeURL, found: false)
    }

    @Test(arguments: StoreSetup.allCases)
    func clearingSearchPassphrase_leavesNoTraceOfOldDigest(setup: StoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { removeStore(at: storeURL) }
        let oldDigest = searchDigester.makeDigest(phrase: "find me")
        let item = note(title: "title", contents: "contents", searchPassphrase: oldDigest)
        let id = try await store.insert(item: item.makeWritable())

        var changed = item.makeWritable()
        changed.searchPassphraseUpdate = .clear
        try await store.update(id: id, item: changed)

        try expectTraces(of: [oldDigest.digest, oldDigest.salt], in: storeURL, found: false)
    }

    /// Rebuilding the database and truncating the log underneath SwiftData must leave it working as before.
    @Test(arguments: StoreSetup.allCases)
    func storeKeepsWorkingAfterScrubbing(setup: StoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { removeStore(at: storeURL) }
        let keptID = try await store.insert(item: note(title: "kept", contents: "kept").makeWritable())
        let ids = try await insertDoomedNotes(into: store)
        try await store.delete(id: ids[0])

        let addedID = try await store.insert(item: note(title: "added", contents: "added").makeWritable())
        try await store.delete(id: ids[1])

        let items = try await store.retrieve(query: .init()).items.map(\.id).reducedToSet()
        #expect(items == [keptID, addedID])
        let reopened = try setup.reopenStore(at: storeURL)
        let reopenedItems = try await reopened.retrieve(query: .init()).items.map(\.id).reducedToSet()
        #expect(reopenedItems == [keptID, addedID])
    }

    /// Deletions an earlier session saved without scrubbing, or columns a migration dropped, are cleared at
    /// the next launch.
    @Test(arguments: StoreSetup.allCases)
    func scrubContentLeftByEarlierSessions_clearsWhatAnEarlierSessionLeft(setup: StoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { removeStore(at: storeURL) }
        try await insertDoomedNotes(into: store)
        try setup.deleteAllItemsWithoutScrubbing(storeURL: storeURL)
        try expectTraces(of: doomedText, in: storeURL, found: true, "an unscrubbed delete should leave the notes")

        await store.scrubContentLeftByEarlierSessions()

        try expectTraces(of: doomedText, in: storeURL, found: false)
    }

    @Test
    func scrub_doesNothingWithoutStoreFile() throws {
        let directory = URL.temporaryDirectory.appending(path: "residue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "vault-primary.sqlite")

        let outcome = PersistedStoreScrubber(storeURL: storeURL).scrub()

        #expect(outcome == .noStore)
        #expect(FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)) == false)
    }

    @Test
    func scrub_doesNothingForStoreInMemory() async throws {
        let store = try PersistedLocalVaultStore.inMemory()

        let outcome = await store.scrubDeletedContent()

        #expect(outcome == .noStore)
    }
}

// MARK: - Store setups

extension PersistedLocalVaultStoreResidueTests {
    /// The ways the SwiftData store is opened on a SQLite file.
    enum StoreSetup: CaseIterable, Sendable, CustomTestStringConvertible {
        /// Opened by `PersistedLocalVaultStoreFactory` as the app opens it: `vault-primary.sqlite`, with the
        /// migration plan.
        case app
        /// `VaultStoreEngine.swiftDataSQLite`, the contract suite's SQLite store.
        case contractEngine

        var testDescription: String {
            switch self {
            case .app: "app"
            case .contractEngine: "contract engine"
            }
        }

        /// A new, empty store, and the URL of its SQLite file.
        func makeStore() async throws -> (PersistedLocalVaultStore, URL) {
            switch self {
            case .app:
                let directory = URL.temporaryDirectory.appending(path: "residue-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
                return (store, directory.appending(path: "vault-primary.sqlite"))
            case .contractEngine:
                let engineStore = try await VaultStoreEngine.swiftDataSQLite.makeStore()
                let store = try #require(engineStore as? PersistedLocalVaultStore)
                let storeURL = await store.storeURL
                return try (store, #require(storeURL))
            }
        }

        /// A second store on the same file.
        func reopenStore(at storeURL: URL) throws -> PersistedLocalVaultStore {
            try PersistedLocalVaultStore(modelContainer: makeContainer(storeURL: storeURL))
        }

        /// Deletes every item through a separate SwiftData container, as an earlier session that never
        /// scrubbed would have.
        func deleteAllItemsWithoutScrubbing(storeURL: URL) throws {
            let context = try ModelContext(makeContainer(storeURL: storeURL))
            try context.delete(model: PersistedVaultItem.self)
            try context.save()
        }

        private func makeContainer(storeURL: URL) throws -> ModelContainer {
            switch self {
            case .app:
                try ModelContainer(
                    for: PersistedVaultItem.self, PersistedVaultTag.self,
                    migrationPlan: PersistedSchemaMigrationPlan.self,
                    configurations: ModelConfiguration(
                        "PersistedLocalVaultStore",
                        schema: .init(versionedSchema: PersistedSchemaLatestVersion.self),
                        url: storeURL,
                    ),
                )
            case .contractEngine:
                try ModelContainer(for: PersistedVaultItem.self, configurations: .init(url: storeURL))
            }
        }
    }
}

// MARK: - Helpers

extension PersistedLocalVaultStoreResidueTests {
    /// Text from the notes each test deletes.
    private var doomedText: [Data] {
        [Data("SHORT-DOOMED-BODY".utf8), Data("LONG-DOOMED-BODY".utf8), Data("DOOMED-TITLE".utf8)]
    }

    @discardableResult
    private func insertDoomedNotes(
        into store: PersistedLocalVaultStore,
        killphrase: String? = nil,
    ) async throws -> [Identifier<VaultItem>] {
        let digest = killphrase.map { killDigester.makeDigest(phrase: $0) }
        let short = note(title: "DOOMED-TITLE", contents: "SHORT-DOOMED-BODY", killphrase: digest)
        // Longer than a page, so SQLite stores it on overflow pages.
        let long = note(
            title: "DOOMED-TITLE",
            contents: String(repeating: "LONG-DOOMED-BODY ", count: 1000),
            killphrase: digest,
        )
        return try await [
            store.insert(item: short.makeWritable()),
            store.insert(item: long.makeWritable()),
        ]
    }

    private func note(
        title: String,
        contents: String,
        killphrase: KillphraseDigest? = nil,
        searchPassphrase: SearchPassphraseDigest? = nil,
    ) -> VaultItem {
        anySecureNote(title: title, contents: contents).wrapInAnyVaultItem(
            searchableLevel: searchPassphrase == nil ? .full : .onlyPassphrase,
            searchPassphrase: searchPassphrase,
            killphrase: killphrase,
        )
    }

    private func expectTraces(
        of needles: [Data],
        in storeURL: URL,
        found expected: Bool,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let storePath = storeURL.path(percentEncoded: false)
        var anyFound = false
        for suffix in ["", "-wal", "-shm"] {
            let path = storePath + suffix
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let contents = try Data(contentsOf: URL(fileURLWithPath: path))
            for needle in needles where contents.range(of: needle) != nil {
                anyFound = true
                if expected == false {
                    Issue.record(
                        "Found deleted content in \(storeURL.lastPathComponent)\(suffix)",
                        sourceLocation: sourceLocation,
                    )
                }
            }
        }
        if expected {
            #expect(anyFound, comment, sourceLocation: sourceLocation)
        }
    }

    private func removeStore(at storeURL: URL) {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }
}
