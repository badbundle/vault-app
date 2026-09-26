import Foundation

/// Encodes a `VaultItemTag.Write` as the `VaultTagRecord` a store persists.
///
/// The tag counterpart of `PersistedVaultItemEncoder`, shared by every store.
struct PersistedVaultTagEncoder {
    /// Encodes a tag whose id is already known, as when importing.
    func encode(tag: VaultItemTag.Write, writeUpdateContext: VaultItemTag.WriteUpdateContext) -> VaultTagRecord {
        VaultTagRecord(
            id: writeUpdateContext.id.id,
            title: tag.name,
            color: encodeColor(tag.color),
            iconName: tag.iconName,
        )
    }

    /// Encodes a new tag, or an update to the `existing` one, which keeps its id.
    func encode(tag: VaultItemTag.Write, existing: VaultTagRecord? = nil) -> VaultTagRecord {
        VaultTagRecord(
            id: existing?.id ?? UUID(),
            title: tag.name,
            color: encodeColor(tag.color),
            iconName: tag.iconName,
        )
    }
}

// MARK: - Helpers

extension PersistedVaultTagEncoder {
    private func encodeColor(_ color: VaultItemColor?) -> PersistedColor? {
        guard let color else { return nil }
        return .init(red: color.red, green: color.green, blue: color.blue)
    }
}
