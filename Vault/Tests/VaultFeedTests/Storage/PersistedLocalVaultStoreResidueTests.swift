import Foundation
import FoundationExtensions
import SQLite3
import SwiftData
import Testing
@testable import VaultFeed

/// Deleted content must not stay in the store's files (MANIFESTO C6): not in the SQLite file, its write-ahead
/// log (`-wal`) or the log's index (`-shm`).
///
/// Each test uses a real store on disk and searches the raw bytes of every file for text that was deleted.
/// Long notes spill onto overflow pages, which SQLite frees whole, so each test deletes both a short and a
/// long one. The tests run against the store as the app opens it and as the contract suite does
/// (`SQLiteStoreSetup`).
struct PersistedLocalVaultStoreResidueTests {
    private let killDigester = KillphraseDigester(key: .zero())
    private let searchDigester = SearchPassphraseDigester(key: .zero())

    @Test(arguments: SQLiteStoreSetup.allCases)
    func killphraseDeletion_leavesNoTraceInStoreFiles(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        try await insertDoomedNotes(into: store, killphrase: "kill me")
        let keptID = try await store.insert(item: note(title: "KEPT-TITLE", contents: "KEPT-BODY").makeWritable())
        try expectTraces(of: doomedText, in: storeURL, found: true, "before deleting, the notes should be on disk")

        let didDelete = await store.deleteItems(matchingKillphrase: "kill me", using: killDigester)

        #expect(didDelete)
        try expectTraces(of: doomedText, in: storeURL, found: false)
        let remaining = try await store.retrieve(query: .init()).items.map(\.id)
        #expect(remaining == [keptID])
    }

    @Test(arguments: SQLiteStoreSetup.allCases)
    func delete_leavesNoTraceInStoreFiles(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        let ids = try await insertDoomedNotes(into: store)

        for id in ids {
            try await store.delete(id: id)
        }

        try expectTraces(of: doomedText, in: storeURL, found: false)
    }

    @Test(arguments: SQLiteStoreSetup.allCases)
    func deleteVault_leavesNoTraceInStoreFiles(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        try await insertDoomedNotes(into: store)

        try await store.deleteVault()

        try expectTraces(of: doomedText, in: storeURL, found: false)
    }

    @Test(arguments: SQLiteStoreSetup.allCases)
    func importAndOverride_leavesNoTraceOfReplacedItems(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        try await insertDoomedNotes(into: store)

        try await store.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [note(title: "IMPORTED-TITLE", contents: "IMPORTED-BODY")],
            tags: [],
        ))

        try expectTraces(of: doomedText, in: storeURL, found: false)
        try expectTraces(of: [Data("IMPORTED-BODY".utf8)], in: storeURL, found: true, "the import should be stored")
    }

    /// Items the import shares with the vault are updated in place rather than deleted, and what they held
    /// before mustn't stay behind either.
    @Test(arguments: SQLiteStoreSetup.allCases)
    func importAndOverride_leavesNoTraceOfOverwrittenItems(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        let ids = try await insertDoomedNotes(into: store)

        try await store.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: ids.map { id in
                VaultItem(
                    metadata: anyVaultItemMetadata(id: id),
                    item: .secureNote(anySecureNote(title: "IMPORTED-TITLE", contents: "IMPORTED-BODY")),
                )
            },
            tags: [],
        ))

        try expectTraces(of: doomedText, in: storeURL, found: false)
        try expectTraces(of: [Data("IMPORTED-BODY".utf8)], in: storeURL, found: true, "the import should be stored")
        let storedIDs = try await store.storedItemIDs()
        #expect(storedIDs == ids.reducedToSet(\.rawValue))
    }

    @Test(arguments: SQLiteStoreSetup.allCases)
    func changingKillphrase_leavesNoTraceOfOldDigest(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        let oldDigest = killDigester.makeDigest(phrase: "old phrase")
        let item = note(title: "title", contents: "contents", killphrase: oldDigest)
        let id = try await store.insert(item: item.makeWritable())

        var changed = item.makeWritable()
        changed.killphraseUpdate = .set(killDigester.makeDigest(phrase: "new phrase"))
        try await store.update(id: id, item: changed)

        try expectTraces(of: [oldDigest.digest, oldDigest.salt], in: storeURL, found: false)
    }

    @Test(arguments: SQLiteStoreSetup.allCases)
    func clearingSearchPassphrase_leavesNoTraceOfOldDigest(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        let oldDigest = searchDigester.makeDigest(phrase: "find me")
        let item = note(title: "title", contents: "contents", searchPassphrase: oldDigest)
        let id = try await store.insert(item: item.makeWritable())

        var changed = item.makeWritable()
        changed.searchPassphraseUpdate = .clear
        try await store.update(id: id, item: changed)

        try expectTraces(of: [oldDigest.digest, oldDigest.salt], in: storeURL, found: false)
    }

    /// SwiftData records every save in Core Data's history tables, `ATRANSACTION` and `ACHANGE`: which item was saved,
    /// which of its fields changed, and when. After a deletion, or a changed killphrase, none of it is left.
    @Test(arguments: SQLiteStoreSetup.allCases)
    func deletingAndEditing_leaveNoHistory(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        let item = note(title: "title", contents: "contents", killphrase: killDigester.makeDigest(phrase: "old"))
        let id = try await store.insert(item: item.makeWritable())
        let doomed = try await insertDoomedNotes(into: store)
        #expect(try historyRowCount(in: storeURL) > 0, "saving should record history")

        var changed = item.makeWritable()
        changed.killphraseUpdate = .set(killDigester.makeDigest(phrase: "new"))
        try await store.update(id: id, item: changed)
        #expect(try historyRowCount(in: storeURL) == 0, "after changing the killphrase")

        try await store.delete(id: doomed[0])
        #expect(try historyRowCount(in: storeURL) == 0, "after deleting an item")

        try await insertDoomedNotes(into: store, killphrase: "kill me")
        #expect(await store.deleteItems(matchingKillphrase: "kill me", using: killDigester))
        #expect(try historyRowCount(in: storeURL) == 0, "after a killphrase deleted items")
    }

    /// History an earlier session left is cleared at the next launch.
    @Test(arguments: SQLiteStoreSetup.allCases)
    func scrubContentLeftByEarlierSessions_clearsHistory(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        try await store.insert(item: note(title: "title", contents: "contents").makeWritable())
        #expect(try historyRowCount(in: storeURL) > 0, "saving should record history")

        await store.scrubContentLeftByEarlierSessions()

        #expect(try historyRowCount(in: storeURL) == 0)
    }

    /// Rebuilding the database and truncating the log underneath SwiftData must leave it working as before.
    @Test(arguments: SQLiteStoreSetup.allCases)
    func storeKeepsWorkingAfterScrubbing(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
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
    @Test(arguments: SQLiteStoreSetup.allCases)
    func scrubContentLeftByEarlierSessions_clearsWhatAnEarlierSessionLeft(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
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

    /// The rows in Core Data's history tables, read through a connection of its own. None if there are no tables.
    private func historyRowCount(in storeURL: URL) throws -> Int {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path(percentEncoded: false), &connection, SQLITE_OPEN_READONLY, nil)
            == SQLITE_OK, let connection
        else {
            sqlite3_close_v2(connection)
            throw StoreReadError()
        }
        defer { sqlite3_close_v2(connection) }
        var total = 0
        for table in ["ATRANSACTION", "ACHANGE"] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM \(table);", -1, &statement, nil) == SQLITE_OK
            else { continue }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw StoreReadError() }
            total += Int(sqlite3_column_int64(statement, 0))
        }
        return total
    }

    private struct StoreReadError: Error {}

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
}
