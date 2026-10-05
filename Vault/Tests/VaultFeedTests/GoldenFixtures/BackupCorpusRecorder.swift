import Foundation
import FoundationExtensions
import PDFKit
import Testing
import VaultBackup
import VaultCore
import VaultExport
import VaultKeygen
@testable import VaultFeed

/// Makes the backups in `Fixtures/Backups/` that aren't there yet, and writes them into the source tree. It only runs
/// when it's asked to:
///
/// ```
/// TEST_RUNNER_VAULT_RECORD_FIXTURES=1 xcodebuild test … -only-testing:VaultFeedTests/BackupCorpusRecorder
/// ```
///
/// It never replaces a backup that's there. It prints each backup's ciphertext length, to be copied into its
/// `BackupCorpusEntry`. See `Fixtures/Backups/README.md`.
@MainActor
@Suite(.enabled(if: GoldenFixture.isRecording), .rendersPDFBackups)
struct BackupCorpusRecorder {
    @Test
    func recordMissingBackups() async throws {
        let recordings: [(BackupCorpusEntry, () async throws -> (data: Data, encryptedLength: Int))] = [
            (.pdfWithRandomPadding, recordPDFWithRandomPadding),
            (.pdfBeforeQuickTypeAndPreview, recordPDFBeforeQuickTypeAndPreview),
            (.pdfWithPlaintextSearchPassphrase, recordPDFWithPlaintextSearchPassphrase),
            (.autoBackup, recordAutoBackup),
            (.transferQRCodes, recordTransferQRCodes),
        ]
        for (entry, record) in recordings where !GoldenFixture.isRecorded(entry.name) {
            let (data, encryptedLength) = try await record()
            try GoldenFixture.record(data, named: entry.name)
            // Only when recording, which has to be asked for.
            // swiftlint:disable:next no_direct_standard_out_logs
            print("Recorded \(entry.name), \(data.count) bytes. Copy into it: encryptedLength \(encryptedLength)")
        }
    }
}

// MARK: - Today's formats

extension BackupCorpusRecorder {
    /// As `AutoBackupServiceImpl` saves one, into a folder: the service itself. It keeps the backup the PDF carries,
    /// as the PDF carries it, rather than the PDF, which is about a megabyte of QR codes.
    private func recordAutoBackup() async throws -> (data: Data, encryptedLength: Int) {
        let source = try await sourceVault()
        let provider = BackupStorageProviderStub(id: "folder")
        let sut = try AutoBackupServiceImpl(
            dataModel: source.dataModel,
            backupEventLogger: BackupEventLoggerMock(),
            clock: clock,
            defaults: Defaults(userDefaults: testUserDefaults()),
            providers: [provider],
        )
        try await source.dataModel.store(backupPassword: backupPassword())
        await sut.selectProvider(id: "folder")

        await sut.forceBackup()

        let written = try #require(provider.writtenData.first)
        let pdf = try #require(PDFDocument(data: written.data))
        let vault = try VaultBackupPDFDetatcherImpl().detachEncryptedVault(fromPDF: pdf)
        return try (EncryptedVaultCoder().encode(vault: vault), vault.data.count)
    }

    /// As a device transfer shows them: `DeviceTransferExportViewModel` itself, with each code read back from the image
    /// it shows.
    private func recordTransferQRCodes() async throws -> (data: Data, encryptedLength: Int) {
        let source = try await sourceVault()
        let codes = try await TransferQRCodes.read(from: source, backupPassword: backupPassword(), clock: clock)
        let vault = try EncryptedVaultCoder().decode(vaultData: TransferQRCodes.join(codes))
        let data = try JSONEncoder.pretty.encode(codes)
        return (data, vault.data.count)
    }
}

// MARK: - Older formats

extension BackupCorpusRecorder {
    /// As the Backups page saved one from #624 to VAULT-75: `BackupCreatePDFViewModel`'s steps, as they were, with
    /// random padding.
    private func recordPDFWithRandomPadding() async throws -> (data: Data, encryptedLength: Int) {
        let source = try await sourceVault()
        let payload = try await source.dataModel.makeExport(userDescription: Self.encryptedDescription)
        let vault = try EncryptedVaultEncoder(clock: clock, backupPassword: backupPassword(), padding: .random)
            .encryptAndEncode(payload: payload)
        return try (pdf(of: vault), vault.data.count)
    }

    /// As the Backups page saved one before #624, which didn't record QuickType or preview choices: today's steps,
    /// with the two left out of every item. They're optional, and a backup leaves out a field that isn't set, so the
    /// payload is what those builds wrote.
    private func recordPDFBeforeQuickTypeAndPreview() async throws -> (data: Data, encryptedLength: Int) {
        let source = try await sourceVault()
        let payload = try await source.dataModel.makeExport(userDescription: Self.encryptedDescription)
        let password = try backupPassword()
        let items = try payload.items.map { item in
            var backupItem = try VaultBackupItemEncoder().encode(storedItem: item)
            backupItem.showInQuickType = nil
            backupItem.previewMode = nil
            return backupItem
        }
        let vault = try VaultBackupEncryptor(
            clock: clock,
            key: password.newVaultKeyWithRandomIV(),
            keygenSalt: password.salt,
            keygenSignature: password.keyDervier.rawValue,
            paddingMode: .random,
        ).encryptBackupPayload(
            items: items,
            tags: payload.tags.map { VaultBackupTagEncoder().encode(tag: $0) },
            userDescription: payload.userDescription,
        )
        return try (pdf(of: vault), vault.data.count)
    }

    /// As the Backups page saved one before #519, with each search passphrase in plain text: made by hand, from the
    /// item as that build's `VaultBackupItemEncoder` wrote it (`LegacyBackupItem`) and its backup steps, which are
    /// today's: the same JSON, compressed with LZMA and sealed with AES-GCM as `VaultEncryptor` seals it.
    private func recordPDFWithPlaintextSearchPassphrase() async throws -> (data: Data, encryptedLength: Int) {
        let source = try await sourceVault()
        let payload = try await source.dataModel.makeExport(userDescription: Self.encryptedDescription)
        let items = try payload.items.map { item in
            try LegacyBackupItem(
                VaultBackupItemEncoder().encode(storedItem: item),
                searchPassphrase: item.metadata.searchPassphrase == nil ? nil : BackupCorpus.searchPassphrase,
            )
        }
        let legacy = LegacyBackupPayload(
            version: "1.0.0",
            created: clock.currentDate,
            userDescription: payload.userDescription,
            tags: payload.tags.map { VaultBackupTagEncoder().encode(tag: $0) },
            items: items,
            // As `VaultBackupEncryptor` chose for a vault of fewer than ten items.
            obfuscationPadding: Data.random(count: .random(in: 300 ..< 3300)),
        )
        let json = try LegacyBackupPayload.encoder.encode(legacy)
        let compressed = try (json as NSData).compressed(using: .lzma) as Data
        let password = try backupPassword()
        let key = try password.newVaultKeyWithRandomIV()
        let sealed = try AESGCMEncryptor(key: key.key.data).encrypt(plaintext: compressed, iv: key.iv.data)
        let vault = EncryptedVault(
            version: "1.0.0",
            data: sealed.ciphertext,
            authentication: sealed.authenticationTag,
            encryptionIV: key.iv.data,
            keygenSalt: password.salt,
            keygenSignature: password.keyDervier.rawValue,
        )
        return try (pdf(of: vault), vault.data.count)
    }
}

// MARK: - Helpers

extension BackupCorpusRecorder {
    private static let userHint = "The password is in the blue notebook."
    /// What the Backups page encrypts into every PDF as the backup's description.
    private static let encryptedDescription = "You can use the Vault app to import this backup."

    private var clock: EpochClockMock {
        EpochClockMock(currentTime: BackupCorpus.created.timeIntervalSince1970)
    }

    /// The backup password, as setting it derives it: with a new salt.
    private func backupPassword() throws -> DerivedEncryptionKey {
        try VaultKeyDeriver.Backup.Fast.v1.createEncryptionKey(password: BackupCorpus.password)
    }

    private func sourceVault() async throws -> RestoreHarness {
        try await RestoreHarness.holdingTheCorpusVault()
    }

    /// The PDF the Backups page makes of a backup, as `BackupCreatePDFViewModel` makes it.
    private func pdf(of vault: EncryptedVault) throws -> Data {
        let document = try VaultBackupPDFGenerator(
            size: A4DocumentSize(),
            documentTitle: "Backup",
            applicationName: "Vault",
            authorName: "Vault",
        ).makePDF(payload: VaultExportPayload(
            encryptedVault: vault,
            userDescription: Self.userHint,
            created: BackupCorpus.created,
        ))
        return try #require(document.dataRepresentation())
    }
}

// MARK: - Before #519

/// A backup item as `VaultBackupItemEncoder` wrote it before #519: a search passphrase in plain text, and neither
/// QuickType nor preview choices. The other fields, and the JSON they're written as, are today's.
private struct LegacyBackupItem: Encodable {
    var id: UUID
    var createdDate: Date
    var updatedDate: Date
    var relativeOrder: UInt64
    var userDescription: String
    var tags: Set<UUID>
    var visibility: VaultBackupItem.Visibility
    var searchableLevel: VaultBackupItem.SearchableLevel
    var searchPassphrase: String?
    var killphraseSalt: Data?
    var killphraseDigest: Data?
    var lockState: VaultBackupItem.LockState
    var tintColor: VaultBackupRGBColor?
    var item: VaultBackupItem.Item

    init(_ item: VaultBackupItem, searchPassphrase: String?) {
        id = item.id
        createdDate = item.createdDate
        updatedDate = item.updatedDate
        relativeOrder = item.relativeOrder
        userDescription = item.userDescription
        tags = item.tags
        visibility = item.visibility
        searchableLevel = item.searchableLevel
        self.searchPassphrase = searchPassphrase
        killphraseSalt = item.killphraseSalt
        killphraseDigest = item.killphraseDigest
        lockState = item.lockState
        tintColor = item.tintColor
        self.item = item.item
    }
}

/// `VaultBackupPayload` before #519, with its items as `LegacyBackupItem`.
private struct LegacyBackupPayload: Encodable {
    var version: SemVer
    var created: Date
    var userDescription: String
    var tags: [VaultBackupTag]
    var items: [LegacyBackupItem]
    var obfuscationPadding: Data

    /// As `IntermediateEncodedVaultEncoder` encodes a payload, then and now.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.nonConformingFloatEncodingStrategy = .throw
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONEncoder {
    /// Readable, and the same every time.
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
