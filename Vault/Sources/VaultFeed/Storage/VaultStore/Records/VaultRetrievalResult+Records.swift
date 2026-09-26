import Foundation

extension VaultRetrievalResult where T == VaultItem {
    /// Decodes records into a retrieval result, keeping their order.
    ///
    /// A record that doesn't decode becomes an error in the result rather than failing the whole retrieval, so one
    /// damaged item never hides the rest.
    static func collectFrom(records: [VaultItemRecord]) -> Self {
        let decoder = PersistedVaultItemDecoder()
        return records.reduce(into: VaultRetrievalResult<VaultItem>()) { result, record in
            do {
                let decodedItem = try decoder.decode(record: record)
                result.items.append(decodedItem)
            } catch let error as VaultItemDecodingError {
                result.errors.append(.failedToDecode(error))
            } catch {
                result.errors.append(.unknown)
            }
        }
    }
}
