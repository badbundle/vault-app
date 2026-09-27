import CoreSpotlight
import Foundation
import FoundationExtensions
import UniformTypeIdentifiers
import VaultFeed

/// Where the codes Spotlight shows are kept.
///
/// @mockable
protocol SpotlightCodeIndex: Sendable {
    /// Replaces everything Vault has in the index with `codes`, which may be none.
    func replace(with codes: [SpotlightCode]) async throws
}

/// Keeps the names of the vault's codes in Spotlight, and Apple Intelligence, which searches it, while the user has
/// turned that on and App Lock is off (VAULT-72). See `SpotlightCode` for what's shown.
///
/// It checks whenever the vault's data changes, and whenever the setting or App Lock does, and replaces what the
/// index holds only when that's changed. Updates run one after another, so the last one always wins: turning App
/// Lock on empties the index even while a fill is underway. The first update after launch always replaces the index,
/// so one left from before, perhaps before App Lock was turned on, is emptied.
@MainActor
final class SpotlightCodeIndexer {
    private let index: any SpotlightCodeIndex
    private let codes: @MainActor () async throws -> [SpotlightCode]
    /// What the index holds, or `nil` if that isn't known: at launch, and after an update failed.
    private var indexed: [SpotlightCode]?
    private var updating: Task<Void, Never>?

    /// - Parameter codes: The codes the index should hold now, and none unless showing them is turned on and App Lock
    ///   is off.
    init(index: any SpotlightCodeIndex, codes: @escaping @MainActor () async throws -> [SpotlightCode]) {
        self.index = index
        self.codes = codes
    }

    /// Brings the index up to date, once any update already underway has finished.
    @discardableResult
    func update() -> Task<Void, Never> {
        let previous = updating
        let task = Task {
            await previous?.value
            await replaceIfChanged()
        }
        updating = task
        return task
    }

    private func replaceIfChanged() async {
        let wanted: [SpotlightCode]
        do {
            wanted = try await codes()
        } catch {
            // The vault couldn't be read: nothing to go on, so the index stays as it is until the next change.
            return
        }
        guard wanted != indexed else { return }
        do {
            try await index.replace(with: wanted)
            indexed = wanted
        } catch {
            indexed = nil
        }
    }
}

/// Vault's codes in the system's Spotlight index.
struct CoreSpotlightCodeIndex: SpotlightCodeIndex {
    private static let indexName = "vault.codes"
    private static let domain = "vault.codes"

    func replace(with codes: [SpotlightCode]) async throws {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        // Readable only while the device is unlocked.
        let index = CSSearchableIndex(name: Self.indexName, protectionClass: .complete)
        try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
        guard codes.isNotEmpty else { return }
        try await index.indexSearchableItems(codes.map(Self.searchableItem(for:)))
    }

    private static func searchableItem(for code: SpotlightCode) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = code.name
        attributes.contentDescription = "Code"
        return CSSearchableItem(
            uniqueIdentifier: code.id.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes,
        )
    }
}

extension NSUserActivity {
    /// The item a Spotlight result opens, if this activity is the user choosing one.
    var spotlightItemID: Identifier<VaultItem>? {
        guard
            activityType == CSSearchableItemActionType,
            let identifier = userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let uuid = UUID(uuidString: identifier)
        else { return nil }
        return Identifier(id: uuid)
    }
}
