import Foundation

/// How an encrypted vault's records are encoded in its slot: as JSON, which the slot file compresses with LZFSE.
///
/// ```
/// { "items": [VaultItemRecord], "tags": [VaultTagRecord] }
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
        let contents = Contents(items: state.items, tags: state.tags)
        return try VaultSlotPayload(version: currentVersion, data: encoder.encode(contents))
    }

    /// - Throws: `EncryptedVaultStoreError.unsupportedPayloadVersion(_:)` for a version this app doesn't know, or a
    ///   decoding error.
    static func decode(_ payload: VaultSlotPayload) throws -> VaultRecordState {
        guard (1 ... currentVersion).contains(payload.version) else {
            throw EncryptedVaultStoreError.unsupportedPayloadVersion(payload.version)
        }
        let contents = try decoder.decode(Contents.self, from: payload.data)
        return VaultRecordState(items: contents.items, tags: contents.tags)
    }

    private struct Contents: Codable {
        var items: [VaultItemRecord]
        var tags: [VaultTagRecord]
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
