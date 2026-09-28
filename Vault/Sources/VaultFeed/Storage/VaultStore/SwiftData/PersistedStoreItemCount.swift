import Foundation
import SQLite3

extension PersistedLocalVaultStoreFactory {
    /// How many items the plain store in `storageDirectory` holds, counted straight from its SQLite file rather than
    /// through SwiftData, or `nil` if there's no store there, or it can't be read, as before the device is first
    /// unlocked.
    ///
    /// The database is opened read-only, and never created, so a store that isn't there stays that way. Reading it
    /// may make the write-ahead log's index, as any reader does, but nothing in the database changes.
    static func storedItemCount(storageDirectory: URL) -> Int? {
        let storeURL = storeFileURLs(storageDirectory: storageDirectory)[0]
        var connection: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path(percentEncoded: false), &connection, SQLITE_OPEN_READONLY, nil)
            == SQLITE_OK, let connection
        else {
            sqlite3_close_v2(connection)
            return nil
        }
        defer { sqlite3_close_v2(connection) }
        sqlite3_busy_timeout(connection, 2000)

        var statement: OpaquePointer?
        // Core Data's table for `PersistedVaultItem`.
        guard sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM ZPERSISTEDVAULTITEM;", -1, &statement, nil)
            == SQLITE_OK
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
