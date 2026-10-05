import CoreImage
import Foundation
import FoundationExtensions
import Testing
import VaultBackup
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// Moving a vault to another device with QR codes, end to end: the codes the transfer screen shows, read back from
/// its images, scanned in any order, then decrypted with the backup password and imported.
@MainActor
struct TransferQRCodeRestoreTests {
    @Test
    func transfer_scannedShuffledWithRepeatsAndAnotherTransfersCode_restoresTheVault() async throws {
        let source = try await RestoreHarness.holdingTheCorpusVault()
        let password = try VaultKeyDeriver.Backup.Fast.v1.createEncryptionKey(password: BackupCorpus.password)
        let codes = try await TransferQRCodes.read(
            from: source,
            backupPassword: password,
            clock: EpochClockMock(currentTime: 100),
        )
        let destination = try RestoreHarness.plain()

        let vault = try scan(TransferQRCodes.asScanned(codes, seed: 1))
        try await destination.restore(encryptedVault: vault, password: BackupCorpus.password)

        #expect(try await destination.vault().items == BackupCorpus.sourceItems().sortedByID)
        #expect(try await Set(destination.vault().tags) == Set(BackupCorpus.tags))
    }

    /// The codes a transfer showed before, in the corpus.
    @Test(arguments: [2, 3, 4] as [UInt64])
    func transferCorpus_scannedShuffledWithRepeatsAndAnotherTransfersCode_restoresTheVault(seed: UInt64) async throws {
        let entry = BackupCorpusEntry.transferQRCodes
        let codes = try JSONDecoder().decode([String].self, from: entry.data())
        let destination = try RestoreHarness.plain()

        let vault = try scan(TransferQRCodes.asScanned(codes, seed: seed))
        try await destination.restore(encryptedVault: vault, password: BackupCorpus.password)

        #expect(vault.data.count == entry.encryptedLength)
        #expect(try await destination.vault().items == entry.restoredItems().sortedByID)
    }

    /// Scans the codes in order with the handler the scanner uses, as the camera reads each.
    private func scan(_ scanned: [TransferQRCodes.Scanned]) throws -> EncryptedVault {
        let handler = BackupImportScanningHandler()
        for (position, code) in scanned.enumerated() {
            let result = handler.decode(data: code.text)
            let isLast = position == scanned.count - 1
            switch result {
            case let .endScanning(.dataRetrieved(vault)):
                #expect(isLast, "Every code was in before the last")
                return vault
            case .continueScanning(.ignore):
                #expect(code.isIgnored, "\(position)")
            case .continueScanning(.success):
                #expect(!code.isIgnored, "\(position)")
            default:
                Issue.record("Unexpected result for code \(position): \(result)")
            }
        }
        throw TransferQRCodes.Incomplete()
    }
}

// MARK: - Codes

enum TransferQRCodes {
    struct Incomplete: Error {}

    /// A code as it's scanned, and whether the scanner should ignore it.
    struct Scanned {
        var text: String
        var isIgnored: Bool
    }

    /// Shows every code of a transfer of `source`'s vault, as the transfer screen does, and reads each back from the
    /// image it shows, as a camera would.
    @MainActor
    static func read(
        from source: RestoreHarness,
        backupPassword: DerivedEncryptionKey,
        clock: EpochClockMock,
    ) async throws -> [String] {
        let timer = IntervalTimerMock()
        let screen = DeviceTransferExportViewModel(
            backupPassword: backupPassword,
            dataModel: source.dataModel,
            clock: clock,
            intervalTimer: timer,
        )
        await screen.generateShards()
        guard case let .displayingQR(_, count) = screen.state else {
            throw Incomplete()
        }
        var codes = [String]()
        for index in 0 ..< count {
            for _ in 0 ..< 100 where screen.state != .displayingQR(currentIndex: index, totalCount: count) {
                await Task.yield()
            }
            #expect(screen.state == .displayingQR(currentIndex: index, totalCount: count))
            let image = try #require(screen.currentQRCodeImage?.pngData())
            // Off the main actor, which the transfer screen and other tests need meanwhile.
            let text = await Task.detached { QRCodeReader.text(inPNG: image) }.value
            try codes.append(#require(text, "Code \(index) didn't read"))
            try await timer.finishTimer(at: index)
        }
        return codes
    }

    /// The codes' contents, joined back together as the scanner joins them.
    static func join(_ codes: [String]) throws -> Data {
        var decoder = DataShardDecoder()
        for code in codes {
            try decoder.add(shardData: Data(code.utf8))
        }
        return try decoder.decodeData()
    }

    /// The codes as someone might scan them: in no particular order, some of them twice, and, after the first, a code
    /// from another transfer. Only the last code scanned completes them.
    static func asScanned(_ codes: [String], seed: UInt64) throws -> [Scanned] {
        var generator = SeededRandomNumberGenerator(seed: seed)
        var remaining = codes.shuffled(using: &generator)
        let last = remaining.removeLast()
        var scanned = remaining.map { Scanned(text: $0, isIgnored: false) }
        for code in remaining.prefix(3) {
            let first = try #require(scanned.firstIndex { $0.text == code })
            let repeated = Int.random(in: first + 1 ... scanned.count, using: &generator)
            scanned.insert(Scanned(text: code, isIgnored: true), at: repeated)
        }
        try scanned.insert(
            Scanned(text: codeFromAnotherTransfer(than: codes[0]), isIgnored: true),
            at: min(1, scanned.count),
        )
        scanned.append(Scanned(text: last, isIgnored: false))
        return scanned
    }

    /// The first code of another transfer, whose codes are of another group.
    private static func codeFromAnotherTransfer(than code: String) throws -> String {
        let group = try EncryptedVaultCoder().decode(dataShard: Data(code.utf8)).group
        let shards = DataShardBuilder { group.id &+ 1 }.makeShards(from: Data(repeating: 0x42, count: 1200))
        let data = try EncryptedVaultCoder().encode(shard: #require(shards.first))
        return try #require(String(bytes: data, encoding: .utf8))
    }
}

/// Reads the text of the QR code in an image, as a camera scanning it would.
enum QRCodeReader {
    static func text(inPNG png: Data) -> String? {
        guard let code = CIImage(data: png) else { return nil }
        // The renderer draws each module as a pixel. Scaled up, on white, with a margin, it reads reliably.
        let scaled = code.samplingNearest().transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let page = CIImage(color: .white).cropped(to: scaled.extent.insetBy(dx: -64, dy: -64))
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh],
        )
        return detector?.features(in: scaled.composited(over: page))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .first
    }
}

extension RestoreHarness {
    /// A plain store holding the vault the corpus is made of.
    static func holdingTheCorpusVault() async throws -> RestoreHarness {
        let harness = try RestoreHarness.plain()
        try await harness.session.importAndOverrideVault(payload: VaultApplicationPayload(
            userDescription: "",
            items: BackupCorpus.sourceItems(),
            tags: BackupCorpus.tags,
        ))
        return harness
    }
}
