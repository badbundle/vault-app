import Foundation
import VaultExport
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
                sealCode: seal.code,
            ),
            content: [],
        )
        document.content.append(.title(makeTitle()))
        document.content.append(.figure(makeSealFigure()))
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

    private var seal: BackupSeal {
        BackupSeal(encryptedVault: payload.encryptedVault)
    }

    /// The backup's seal, and what it's for, so a PDF and the seal Check a Backup shows can be matched.
    private func makeSealFigure() -> DataBlockFigure {
        let seal = seal
        let sealSize: CGFloat = 64
        return DataBlockFigure(
            name: "Seal \(seal.code)",
            height: sealSize,
            padding: .init(top: 4, left: 0, bottom: 8, right: 0),
        ) { context, rect in
            let sealRect = CGRect(x: rect.minX, y: rect.minY, width: sealSize, height: sealSize)
            BackupSealArtwork(seal: seal).draw(in: context, rect: sealRect)

            let textX = sealRect.maxX + 14
            let textWidth = rect.maxX - textX
            let code = NSAttributedString(
                string: localized(key: "Seal \(seal.code)"),
                attributes: [
                    .font: PlatformFont.monospacedSystemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: PlatformColor.black,
                ],
            )
            let caption = NSAttributedString(
                string: localized(
                    key: "Every copy of this backup has this seal. When Vault checks or restores it, the seal it shows should match.",
                ),
                attributes: [
                    .font: PlatformFont.systemFont(ofSize: 8),
                    .foregroundColor: PlatformColor.gray,
                ],
            )
            let codeHeight = code.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                context: nil,
            ).height
            let captionHeight = caption.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                context: nil,
            ).height
            let gap: CGFloat = 3
            let top = rect.minY + (sealSize - codeHeight - gap - captionHeight) / 2
            code.draw(in: CGRect(x: textX, y: top, width: textWidth, height: codeHeight))
            caption.draw(in: CGRect(x: textX, y: top + codeHeight + gap, width: textWidth, height: captionHeight))
        }
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
