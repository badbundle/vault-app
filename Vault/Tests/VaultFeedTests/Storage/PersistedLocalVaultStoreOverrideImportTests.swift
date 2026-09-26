import Foundation
import FoundationExtensions
import SQLite3
import Testing
@testable import VaultFeed

/// An override import that fails part way through saving, as a full disk would make it, leaves the vault as it
/// was, on disk as well as in the store.
///
/// The fault is injected into SQLite itself: a trigger fails the save's transaction when it comes to insert a
/// particular item, in a save that also deletes, updates and adds other rows. The contract suite covers a
/// failure before saving (`importAndOverrideVault_failingPartWayLeavesVaultUntouched`).
struct PersistedLocalVaultStoreOverrideImportTests {
    @Test(arguments: SQLiteStoreSetup.allCases)
    func importAndOverride_saveFailingPartWayLeavesVaultUntouched(setup: SQLiteStoreSetup) async throws {
        let (store, storeURL) = try await setup.makeStore()
        defer { SQLiteStoreSetup.removeStore(at: storeURL) }
        let tag = anyVaultItemTag(name: "Kept")
        let kept = [
            uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 50), userDescription: "one", tags: [tag.id]),
            uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100), userDescription: "two"),
        ]
        try await store.importAndOverrideVault(payload: .init(userDescription: "", items: kept, tags: [tag]))
        let itemsBefore = try await store.allVaultItems()
        let tagsBefore = try await store.allVaultTags()
        try injectFault(intoStoreAt: storeURL, whenInsertingItemDescribed: "FAULT")

        let payload = VaultApplicationPayload(
            userDescription: "",
            items: [
                uniqueVaultItem(id: kept[0].id, updatedDate: Date(timeIntervalSince1970: 1000), userDescription: "new"),
                uniqueVaultItem(userDescription: "added"),
                uniqueVaultItem(userDescription: "FAULT"),
            ],
            tags: [anyVaultItemTag(name: "New")],
        )
        await #expect(throws: (any Error).self) {
            try await store.importAndOverrideVault(payload: payload)
        }

        try await store.assertStoreContains(exactlyItems: itemsBefore)
        try await store.assertStoreContains(exactlyTags: tagsBefore)
        let reopened = try setup.reopenStore(at: storeURL)
        try await reopened.assertStoreContains(exactlyItems: itemsBefore)
        try await reopened.assertStoreContains(exactlyTags: tagsBefore)

        // And the store isn't left stuck: the same import without the fault goes through.
        try removeFault(fromStoreAt: storeURL)
        try await store.importAndOverrideVault(payload: payload)
        let items = try await store.allVaultItems()
        #expect(items.map(\.metadata.userDescription).sorted() == ["FAULT", "added", "new"])
    }
}

// MARK: - Helpers

extension PersistedLocalVaultStoreOverrideImportTests {
    /// Makes SQLite fail any statement that inserts an item with this description, which fails the whole save.
    ///
    /// The trigger fails with a runtime error (an integer overflow), which Core Data reports as a failed save.
    private func injectFault(intoStoreAt storeURL: URL, whenInsertingItemDescribed description: String) throws {
        try withConnection(to: storeURL) { connection in
            let table = try #require(itemTableName(connection: connection))
            let sql = """
            CREATE TRIGGER inject_fault BEFORE INSERT ON \(table)
            WHEN NEW.ZUSERDESCRIPTION = '\(description)'
            BEGIN SELECT abs(-9223372036854775807 - 1); END;
            """
            try #require(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
        }
    }

    private func removeFault(fromStoreAt storeURL: URL) throws {
        try withConnection(to: storeURL) { connection in
            try #require(sqlite3_exec(connection, "DROP TRIGGER inject_fault;", nil, nil, nil) == SQLITE_OK)
        }
    }

    /// The table Core Data keeps `PersistedVaultItem` in.
    private func itemTableName(connection: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ZPERSISTEDVAULTITEM';"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let name = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: name)
    }

    private func withConnection(to storeURL: URL, _ body: (OpaquePointer) throws -> Void) throws {
        var connection: OpaquePointer?
        defer { sqlite3_close_v2(connection) }
        try #require(
            sqlite3_open_v2(storeURL.path(percentEncoded: false), &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
        )
        sqlite3_busy_timeout(connection, 2000)
        try body(#require(connection))
    }
}
