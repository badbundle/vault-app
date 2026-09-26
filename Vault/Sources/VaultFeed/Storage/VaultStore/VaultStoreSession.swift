import Foundation
import FoundationExtensions
import VaultCore

/// Everything a vault store does: what `VaultDataModel` reads and writes through.
public typealias CompleteVaultStore = VaultStore & VaultStoreDeleter & VaultStoreImporter &
    VaultStoreKillphraseDeleter &
    VaultTagStore

/// The vault store the app reads and writes, whichever one that is right now.
///
/// Forwards every call to its `target`, which can change while the app runs: the plain SQLite store, or nothing at
/// all while the vault is `locked`. (The encrypted store joins as a target once it exists: see
/// `docs/on-device-encryption.md`, "Store session".) Everything else holds on to the session, so switching the target
/// switches the store for all of them.
///
/// While locked, reads find nothing and writes throw `VaultStoreSessionError.locked`. Exporting throws too, rather
/// than exporting an empty vault that a backup could replace a real one with. Deleting by killphrase finds nothing,
/// exactly as it does for a phrase that matches nothing (MANIFESTO C2).
public final actor VaultStoreSession {
    public enum Target: Sendable {
        /// Today's SQLite store, readable whenever the device is unlocked.
        case plain(any CompleteVaultStore)
        /// No store: the vault is locked.
        case locked
    }

    private var target: Target
    /// Calls that reached a store and haven't returned yet.
    private var operationsInFlight = 0
    private var waitingForOperations = [CheckedContinuation<Void, Never>]()

    public init(target: Target) {
        self.target = target
    }

    public var isLocked: Bool {
        if case .locked = target {
            true
        } else {
            false
        }
    }

    /// Switch to another target. New calls go to it at once; this returns once every call already made to the old
    /// one has finished, so the old store isn't in use any more.
    public func switchTo(_ newTarget: Target) async {
        target = newTarget
        await waitForOperationsInFlight()
    }

    /// Switch to `locked`, once every call already underway has finished.
    public func lock() async {
        await switchTo(.locked)
    }

    private func waitForOperationsInFlight() async {
        guard operationsInFlight > 0 else { return }
        await withCheckedContinuation { continuation in
            waitingForOperations.append(continuation)
        }
    }

    /// Runs `operation` against the current store, or throws `VaultStoreSessionError.locked` if there's none.
    private func withStore<T: Sendable>(_ operation: (any CompleteVaultStore) async throws -> T) async throws -> T {
        guard case let .plain(store) = target else {
            throw VaultStoreSessionError.locked
        }
        operationsInFlight += 1
        defer { operationDidFinish() }
        return try await operation(store)
    }

    /// Runs `operation` against the current store, or gives `valueWhenLocked` if there's none.
    private func withStore<T: Sendable>(
        orWhenLocked valueWhenLocked: T,
        _ operation: (any CompleteVaultStore) async throws -> T,
    ) async throws -> T {
        guard !isLocked else { return valueWhenLocked }
        return try await withStore(operation)
    }

    private func operationDidFinish() {
        operationsInFlight -= 1
        guard operationsInFlight == 0 else { return }
        let waiting = waitingForOperations
        waitingForOperations.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }
}

/// Why a store call failed without reaching a store.
public enum VaultStoreSessionError: Error, Equatable, Sendable {
    /// The vault is locked, so there's no store to write to.
    case locked
}

// MARK: - Reading

extension VaultStoreSession: VaultStoreReader {
    public func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        try await withStore(orWhenLocked: .empty()) { store in
            try await store.retrieve(query: query, searchPassphraseMatcher: searchPassphraseMatcher)
        }
    }

    public var hasAnyItems: Bool {
        get async throws {
            try await withStore(orWhenLocked: false) { store in
                try await store.hasAnyItems
            }
        }
    }
}

extension VaultStoreSession: VaultTagStoreReader {
    public func retrieveTags() async throws -> [VaultItemTag] {
        try await withStore(orWhenLocked: []) { store in
            try await store.retrieveTags()
        }
    }
}

extension VaultStoreSession: VaultStoreExporter {
    public func exportVault(userDescription: String) async throws -> VaultApplicationPayload {
        try await withStore { store in
            try await store.exportVault(userDescription: userDescription)
        }
    }
}

// MARK: - Writing

extension VaultStoreSession: VaultStoreWriter {
    @discardableResult
    public func insert(item: VaultItem.Write) async throws -> Identifier<VaultItem> {
        try await withStore { store in
            try await store.insert(item: item)
        }
    }

    public func update(id: Identifier<VaultItem>, item: VaultItem.Write) async throws {
        try await withStore { store in
            try await store.update(id: id, item: item)
        }
    }

    public func delete(id: Identifier<VaultItem>) async throws {
        try await withStore { store in
            try await store.delete(id: id)
        }
    }
}

extension VaultStoreSession: VaultStoreHOTPIncrementer {
    public func incrementCounter(id: Identifier<VaultItem>) async throws {
        try await withStore { store in
            try await store.incrementCounter(id: id)
        }
    }
}

extension VaultStoreSession: VaultStoreReorderable {
    public func reorder(items: Set<Identifier<VaultItem>>, to position: VaultReorderingPosition) async throws {
        try await withStore { store in
            try await store.reorder(items: items, to: position)
        }
    }
}

extension VaultStoreSession: VaultTagStoreWriter {
    @discardableResult
    public func insertTag(item: VaultItemTag.Write) async throws -> Identifier<VaultItemTag> {
        try await withStore { store in
            try await store.insertTag(item: item)
        }
    }

    public func updateTag(id: Identifier<VaultItemTag>, item: VaultItemTag.Write) async throws {
        try await withStore { store in
            try await store.updateTag(id: id, item: item)
        }
    }

    public func deleteTag(id: Identifier<VaultItemTag>) async throws {
        try await withStore { store in
            try await store.deleteTag(id: id)
        }
    }
}

extension VaultStoreSession: VaultStoreImporter {
    public func importAndMergeVault(payload: VaultApplicationPayload) async throws {
        try await withStore { store in
            try await store.importAndMergeVault(payload: payload)
        }
    }

    public func importAndOverrideVault(payload: VaultApplicationPayload) async throws {
        try await withStore { store in
            try await store.importAndOverrideVault(payload: payload)
        }
    }
}

extension VaultStoreSession: VaultStoreDeleter {
    public func deleteVault() async throws {
        try await withStore { store in
            try await store.deleteVault()
        }
    }
}

extension VaultStoreSession: VaultStoreKillphraseDeleter {
    @discardableResult
    public func deleteItems(matchingKillphrase: String, using matcher: any KillphraseMatcher) async -> Bool {
        // Never throws: locked reads as "nothing matched", the same as every other way this finds nothing.
        (try? await withStore(orWhenLocked: false) { store in
            await store.deleteItems(matchingKillphrase: matchingKillphrase, using: matcher)
        }) ?? false
    }
}
