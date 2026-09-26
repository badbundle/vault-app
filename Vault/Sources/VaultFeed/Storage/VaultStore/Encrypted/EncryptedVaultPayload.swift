import Foundation

/// How an encrypted vault's records are encoded in its slot: as JSON, which the slot file compresses with LZFSE.
///
/// ```
/// { "items": [VaultItemRecord], "tags": [VaultTagRecord], "vault": VaultMetadata }
/// ```
///
/// - **Keys** are the records' property names.
/// - **Dates** are `Date`'s own encoding, seconds since 2001, which reads back exactly. Milliseconds since 1970 would
///   round about half of all dates, and a vault read back would no longer equal the one saved.
/// - **Data** is base64.
///
/// **Versions.** The slot's body records the payload version (`VaultSlotPayload.version`). A later version may add
/// fields, and must read every earlier one. This version refuses anything newer than itself, rather than dropping
/// what it doesn't understand the next time it saves.
enum EncryptedVaultPayload {
    static let currentVersion: UInt32 = 1

    static func encode(_ state: VaultRecordState) throws -> VaultSlotPayload {
        let contents = Contents(items: state.items, tags: state.tags, vault: state.vault)
        return try VaultSlotPayload(version: currentVersion, data: encoder.encode(contents))
    }

    /// Opens and decodes the payload of a slot opened in `file`, then wipes the JSON it decoded.
    ///
    /// - Throws: As `VaultSlotFile.openPayload(of:)` and `decode(_:)` do.
    static func decode(slot: VaultSlotFile.OpenedSlot, in file: VaultSlotFile) throws -> VaultRecordState {
        var payload = try file.openPayload(of: slot)
        defer { SlotRandom.wipe(&payload.data) }
        return try decode(payload)
    }

    /// - Throws: `EncryptedVaultStoreError.unsupportedPayloadVersion(_:)` for a version this app doesn't know, or a
    ///   decoding error.
    static func decode(_ payload: VaultSlotPayload) throws -> VaultRecordState {
        guard (1 ... currentVersion).contains(payload.version) else {
            throw EncryptedVaultStoreError.unsupportedPayloadVersion(payload.version)
        }
        let contents = try decoder.decode(Contents.self, from: payload.data)
        return VaultRecordState(items: contents.items, tags: contents.tags, vault: contents.vault)
    }

    private struct Contents: Codable {
        var items: [VaultItemRecord]
        var tags: [VaultTagRecord]
        var vault: VaultMetadata

        init(items: [VaultItemRecord], tags: [VaultTagRecord], vault: VaultMetadata) {
            self.items = items
            self.tags = tags
            self.vault = vault
        }

        /// A missing `vault` reads as no metadata: fields added later read as their defaults when they're missing.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decode([VaultItemRecord].self, forKey: .items)
            tags = try container.decode([VaultTagRecord].self, forKey: .tags)
            vault = try container.decodeIfPresent(VaultMetadata.self, forKey: .vault) ?? VaultMetadata()
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.dataDecodingStrategy = .base64
        return decoder
    }
}
