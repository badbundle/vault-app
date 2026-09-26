import Foundation

/// A stored tag as plain values: every field of `PersistedVaultTag`, in the raw form it's persisted in.
///
/// The counterpart of `VaultItemRecord` for tags. Which items carry a tag is recorded on the items
/// (`VaultItemRecord.tagIDs`), so the record has no list of items. Like item records, its property names are the
/// keys of an encrypted vault's JSON.
struct VaultTagRecord: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    /// `nil` for tags stored without a color, which decode to the default tag color.
    var color: PersistedColor?
    /// `nil` for tags stored without an icon, which decode to the default tag icon.
    var iconName: String?
}
