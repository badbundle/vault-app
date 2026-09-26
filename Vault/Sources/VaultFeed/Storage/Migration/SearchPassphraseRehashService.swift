import Foundation

/// Phase B of the V2 → V3 search-passphrase migration.
///
/// Reads plaintext passphrases stashed by the V2 → V3 schema migration's
/// `willMigrate` handler, hashes them with the unlocked vault's digester,
/// writes the digest + salt back onto the corresponding `PersistedVaultItem`,
/// and deletes the pending file.
///
/// Idempotent: if the pending file is empty or missing, `run` is a no-op.
/// Crash-safe: any entry not successfully written remains in the pending
/// file and will be retried on the next call.
public struct SearchPassphraseRehashService: Sendable {
    public typealias Writer = @Sendable (UUID, SearchPassphraseDigest) async throws -> Void

    private let pendingStore: PendingSearchPassphraseRehashStore
    private let writer: Writer

    init(pendingStore: PendingSearchPassphraseRehashStore, writer: @escaping Writer) {
        self.pendingStore = pendingStore
        self.writer = writer
    }

    public init(storeDirectory: URL, fileManager: FileManager = .default, writer: @escaping Writer) {
        self.init(
            pendingStore: PendingSearchPassphraseRehashStore(
                fileURL: PendingSearchPassphraseRehashStore.defaultURL(storeDirectory: storeDirectory),
                fileManager: fileManager,
            ),
            writer: writer,
        )
    }

    /// Runs the rehash pass. Safe to call repeatedly; if there are no
    /// pending entries it returns immediately. Errors during write leave
    /// the corresponding entries in the pending file for a future retry.
    public func run(using digester: SearchPassphraseDigester) async {
        let entries: [PendingSearchPassphraseRehashStore.Entry]
        do {
            entries = try pendingStore.read()
        } catch is DecodingError {
            // A file that can't be decoded holds nothing this or any later run could use, so don't leave its
            // plaintext behind.
            try? pendingStore.clear()
            return
        } catch {
            // Couldn't read it right now: leave it for the next run.
            return
        }
        guard entries.isEmpty == false else { return }

        var remaining: [PendingSearchPassphraseRehashStore.Entry] = []
        for entry in entries {
            let digest = digester.makeDigest(phrase: entry.phrase)
            do {
                try await writer(entry.itemID, digest)
            } catch {
                remaining.append(entry)
            }
        }

        if remaining.isEmpty {
            try? pendingStore.clear()
        } else {
            try? pendingStore.write(remaining)
        }
    }
}
