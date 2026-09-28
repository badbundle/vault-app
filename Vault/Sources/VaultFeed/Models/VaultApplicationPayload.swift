import CryptoEngine
import Foundation
import FoundationExtensions

/// A complete manifest of the users data.
///
/// This is the data model used at the application-level for importing and exporting the vault.
public struct VaultApplicationPayload: Sendable, Equatable, Hashable {
    public var userDescription: String
    public var items: [VaultItem]
    public var tags: [VaultItemTag]
    /// The keys the items' killphrase digests can have been made with: every key on the keyring of the device the
    /// vault was exported from, its own first (`VaultDataModel.makeExport(userDescription:)`). They go with the vault,
    /// so its killphrases still work wherever it's restored. Empty straight from a store, and from a backup made
    /// before they were included.
    public var killphraseKeys: [KeyData<32>]
    /// The keys the items' search passphrase digests can have been made with, as `killphraseKeys`.
    public var searchPassphraseKeys: [KeyData<32>]

    public init(
        userDescription: String,
        items: [VaultItem],
        tags: [VaultItemTag],
        killphraseKeys: [KeyData<32>] = [],
        searchPassphraseKeys: [KeyData<32>] = [],
    ) {
        self.userDescription = userDescription
        self.items = items
        self.tags = tags
        self.killphraseKeys = killphraseKeys
        self.searchPassphraseKeys = searchPassphraseKeys
    }
}

// MARK: - Digestable

extension VaultApplicationPayload: Digestable {
    public var digestableData: some Encodable {
        // The user description is not included in the digest.
        // We only want the digest to represent substantive data so we can compare when data has changed.
        struct DigestPayload<I: Encodable, T: Encodable>: Encodable {
            public var items: [I]
            public var tags: [T]
        }
        return DigestPayload(
            items: items.map(\.digestableData),
            tags: tags.map(\.digestableData),
        )
    }
}
