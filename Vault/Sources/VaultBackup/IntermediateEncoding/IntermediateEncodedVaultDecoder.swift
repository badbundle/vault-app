import Foundation

/// Decodes raw data to a vault backup payload object.
final class IntermediateEncodedVaultDecoder {
    init() {}

    func decode(encodedVault: IntermediateEncodedVault) throws -> VaultBackupPayload {
        let decompressed = try BoundedLZMADecompression.decompress(encodedVault.data)
        return try makeDecoder().decode(VaultBackupPayload.self, from: decompressed)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.dataDecodingStrategy = .base64
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.nonConformingFloatDecodingStrategy = .throw
        return decoder
    }
}
