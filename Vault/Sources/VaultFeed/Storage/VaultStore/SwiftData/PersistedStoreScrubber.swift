import Foundation
import SQLite3

/// Clears what deleted content leaves behind in the SwiftData store's SQLite files (MANIFESTO C6).
///
/// Two things keep deleted content on disk after SwiftData saves a deletion:
///
/// - **The write-ahead log.** The store runs in WAL mode, so a save only appends the changed pages to
///   `-wal`. Earlier frames, holding the item as it was, stay in the log until a checkpoint. SQLite only
///   checkpoints on its own once the log reaches about 1,000 pages, and the app keeps the store open all
///   session, so that can take a long time.
/// - **Freed pages.** The system SQLite runs with `secure_delete = FAST`. That zeroes a deleted row inside
///   its page, but a page freed whole, such as the overflow pages of a long note, goes onto the freelist
///   with its content intact. SwiftData gives no way to change the setting on Core Data's own connection.
///
/// So this opens a second, short-lived connection to the same file and runs `VACUUM`, which rebuilds the
/// database from its live rows so no freed page or cell survives, then `PRAGMA wal_checkpoint(TRUNCATE)`,
/// which copies the log into the database and truncates the log to zero bytes. SQLite's own locking
/// coordinates the two connections, as it does between the app and its extensions, so Core Data picks up
/// the result like any other write. `-shm` only ever holds the log's index, never content.
///
/// Anything that keeps a read open on the store (another process, for example) can stop the checkpoint
/// from finishing. The log is then left as it was, and the next scrub finishes the job.
struct PersistedStoreScrubber {
    enum Outcome: Equatable {
        /// Deleted content was cleared and the log is empty.
        case scrubbed
        /// There was no store file to scrub.
        case noStore
        /// The store was busy or failed, so deleted content may remain until the next scrub.
        case incomplete
    }

    enum Vacuum {
        /// Always rebuild the database, for straight after something is deleted.
        case always
        /// Only rebuild it if it has freed pages, which is enough to clear anything left from an earlier
        /// session: SQLite zeroes deleted rows within a page as it deletes them.
        case ifPagesWereFreed
    }

    var storeURL: URL
    /// How long to wait for another connection to finish, in milliseconds.
    var busyTimeout: Int32 = 2000

    func scrub(vacuum: Vacuum = .always) -> Outcome {
        var connection: OpaquePointer?
        // Read-write without create: a store that isn't there has nothing to scrub, and mustn't be created.
        guard sqlite3_open_v2(storeURL.path(percentEncoded: false), &connection, SQLITE_OPEN_READWRITE, nil)
            == SQLITE_OK, let connection
        else {
            sqlite3_close_v2(connection)
            return .noStore
        }
        defer { sqlite3_close_v2(connection) }
        sqlite3_busy_timeout(connection, busyTimeout)

        let shouldVacuum = switch vacuum {
        case .always: true
        case .ifPagesWereFreed: freelistCount(connection: connection).map { $0 > 0 } ?? true
        }
        if shouldVacuum, sqlite3_exec(connection, "VACUUM;", nil, nil, nil) != SQLITE_OK {
            return .incomplete
        }

        var logFrames: Int32 = 0
        var checkpointedFrames: Int32 = 0
        let checkpoint = sqlite3_wal_checkpoint_v2(
            connection,
            nil,
            SQLITE_CHECKPOINT_TRUNCATE,
            &logFrames,
            &checkpointedFrames,
        )
        return checkpoint == SQLITE_OK ? .scrubbed : .incomplete
    }

    private func freelistCount(connection: OpaquePointer) -> Int? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "PRAGMA freelist_count;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
