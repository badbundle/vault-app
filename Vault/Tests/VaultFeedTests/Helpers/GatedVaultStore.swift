import Foundation
@testable import VaultFeed

/// A vault store that records the calls it gets and can hold them until the test lets them go, for checking what
/// happens while a call is underway.
actor GatedVaultStore: CompleteVaultStore {
    private(set) var calls = [String]()
    private var items = [VaultItem]()
    private var tags = [VaultItemTag]()
    private var killphraseDeletes = false
    private var isHolding = false
    private var heldCalls = [CheckedContinuation<Void, Never>]()

    init(items: [VaultItem] = [], tags: [VaultItemTag] = [], killphraseDeletes: Bool = false) {
        self.items = items
        self.tags = tags
        self.killphraseDeletes = killphraseDeletes
    }

    /// Holds every call from now on, until `release()`.
    func hold() {
        isHolding = true
    }

    /// Lets every held call finish, and stops holding new ones.
    func release() {
        isHolding = false
        let held = heldCalls
        heldCalls.removeAll()
        for call in held {
            call.resume()
        }
    }

    /// Waits (for up to 5 seconds) until `count` calls are being held.
    func waitUntilHolding(_ count: Int = 1) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while heldCalls.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func enter(_ call: String) async {
        calls.append(call)
        guard isHolding else { return }
        await withCheckedContinuation { continuation in
            heldCalls.append(continuation)
        }
    }

    // MARK: - CompleteVaultStore

    func retrieve(
        query _: VaultStoreQuery,
        searchPassphraseMatcher _: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        await enter("retrieve")
        return .init(items: items)
    }

    var hasAnyItems: Bool {
        get async throws {
            await enter("hasAnyItems")
            return items.isNotEmpty
        }
    }

    func insert(item _: VaultItem.Write) async throws -> Identifier<VaultItem> {
        await enter("insert")
        return .new()
    }

    func update(id _: Identifier<VaultItem>, item _: VaultItem.Write) async throws {
        await enter("update")
    }

    func delete(id _: Identifier<VaultItem>) async throws {
        await enter("delete")
    }

    func incrementCounter(id _: Identifier<VaultItem>) async throws {
        await enter("incrementCounter")
    }

    func reorder(items _: Set<Identifier<VaultItem>>, to _: VaultReorderingPosition) async throws {
        await enter("reorder")
    }

    func exportVault(userDescription: String) async throws -> VaultApplicationPayload {
        await enter("exportVault")
        return VaultApplicationPayload(userDescription: userDescription, items: items, tags: tags)
    }

    func importAndMergeVault(payload _: VaultApplicationPayload) async throws {
        await enter("importAndMergeVault")
    }

    func importAndOverrideVault(payload _: VaultApplicationPayload) async throws {
        await enter("importAndOverrideVault")
    }

    func deleteVault() async throws {
        await enter("deleteVault")
    }

    func deleteItems(matchingKillphrase _: String, using _: any KillphraseMatcher) async -> Bool {
        await enter("deleteItems")
        return killphraseDeletes
    }

    func retrieveTags() async throws -> [VaultItemTag] {
        await enter("retrieveTags")
        return tags
    }

    func insertTag(item _: VaultItemTag.Write) async throws -> Identifier<VaultItemTag> {
        await enter("insertTag")
        return .new()
    }

    func updateTag(id _: Identifier<VaultItemTag>, item _: VaultItemTag.Write) async throws {
        await enter("updateTag")
    }

    func deleteTag(id _: Identifier<VaultItemTag>) async throws {
        await enter("deleteTag")
    }
}
