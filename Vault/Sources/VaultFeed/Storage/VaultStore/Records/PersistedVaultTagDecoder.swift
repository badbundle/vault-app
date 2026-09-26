import Foundation

/// Decodes a stored `VaultTagRecord` into a `VaultItemTag`.
///
/// The counterpart of `PersistedVaultTagEncoder`, shared by every store.
struct PersistedVaultTagDecoder {
    func decode(record: VaultTagRecord) throws -> VaultItemTag {
        .init(
            id: .init(id: record.id),
            name: record.title,
            color: decodeColor(record.color),
            iconName: record.iconName ?? VaultItemTag.defaultIconName,
        )
    }
}

// MARK: - Helpers

extension PersistedVaultTagDecoder {
    private func decodeColor(_ color: PersistedColor?) -> VaultItemColor {
        guard let color else { return .tagDefault }
        return .init(red: color.red, green: color.green, blue: color.blue)
    }
}
