import Foundation
import VaultExport

/// Helper for creating the data block document from an exported vault.
struct VaultExportDataBlockGenerator {
    private let payload: VaultExportPayload
    private let dataShardBuilder: DataShardBuilder

    init(payload: VaultExportPayload, dataShardBuilder: DataShardBuilder = DataShardBuilder()) {
        self.payload = payload
        self.dataShardBuilder = dataShardBuilder
    }

    func makeDocument(knownPageCount: Int) throws -> DataBlockDocument {
        var document = DataBlockDocument(
            headerGenerator: VaultExportDataBlockHeaderGenerator(
                dateCreated: payload.created,
                totalNumberOfPages: knownPageCount,
            ),
            content: [],
        )
        document.content.append(.title(makeTitle()))
        for descriptionLabel in makeUserDescriptionLabels() {
            document.content.append(.title(descriptionLabel))
        }
        let encodedShards = try makeEncodedShardsFromVault()
        document.content.append(.title(makeQRCodeHelperLabel(totalCodes: encodedShards.count)))
        document.content.append(.dataBlock(encodedShards))
        return document
    }
}

extension VaultExportDataBlockGenerator {
    private func makeTitle() -> DataBlockLabel {
        .init(
            text: localized(key: "Vault Export"),
            font: .systemFont(ofSize: 26, weight: .heavy),
            padding: .init(top: 8, left: 0, bottom: 8, right: 0),
        )
    }

    private func makeUserDescriptionLabels() -> [DataBlockLabel] {
        payload.userDescription
            .split(separator: "\n")
            .compactMap { text in
                if text.isEmpty {
                    return nil
                }
                return .init(
                    text: String(text),
                    font: .systemFont(ofSize: 10),
                    padding: .zero,
                )
            }
    }

    private func makeQRCodeHelperLabel(totalCodes: Int) -> DataBlockLabel {
        .init(
            text: localized(
                key: "Your backup is contained within the following QR codes in an encrypted format. To import this backup, you should open the Vault app and scan every code during the import. In this export, there are \(totalCodes) QR codes.",
            ),
            font: .systemFont(ofSize: 8),
            textColor: .gray,
            padding: .init(top: 12, left: 0, bottom: 8, right: 0),
        )
    }

    private func makeEncodedShardsFromVault() throws -> [Data] {
        let coder = EncryptedVaultCoder()
        let encodedVault = try coder.encode(vault: payload.encryptedVault)
        let shardEncoder = DataShardEncoder(dataShardBuilder: dataShardBuilder)
        return try shardEncoder.makeEncodedShards(fromData: encodedVault)
    }
}
