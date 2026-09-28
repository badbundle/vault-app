import Combine
import Foundation
import FoundationExtensions
import PDFKit
import SwiftData
import Testing
import VaultBackup
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// The backup corpus in `Fixtures/Backups/`: a backup in every format the app still has to restore, each made once
/// and kept as it was made. They're all backups of the same vault (`sourceItems()`, `tags`), and each restores to it
/// as its format carried it. See `Fixtures/Backups/README.md`.
struct BackupCorpusEntry: Sendable, CustomTestStringConvertible {
    /// What a format carried of the vault, which is what restoring it gives back.
    enum Format: Sendable {
        /// Everything, as backups have since QuickType and note previews were recorded (#624).
        case current
        /// Everything but whether each code is offered in QuickType and how much of each note the feed shows, which
        /// restore as they always did: offered, and the title and first line.
        case beforeQuickTypeAndPreview
        /// As `beforeQuickTypeAndPreview`, with each search passphrase in plain text (before #519), which restoring
        /// drops: the item keeps its visibility, with no passphrase.
        case plaintextSearchPassphrase
    }

    /// How the file holds the backup.
    enum Form: Sendable {
        /// A PDF, as the Backups page or auto-backup saves one.
        case pdf
        /// The `EncryptedVault` a PDF carries, as `EncryptedVaultCoder` encodes it: the backup, once the import flow
        /// has read it out of its PDF.
        case encryptedVault
        /// The QR codes a device transfer shows, in the order it shows them: a JSON array of each code's text.
        case qrCodes
    }

    enum Padding: Sendable {
        /// Just under 32 KiB of ciphertext, as saved backups have been since VAULT-75.
        case toFixedSize
        /// A random amount, as every backup was before VAULT-75, and a device transfer still is.
        case random
    }

    /// The file's path in `Fixtures/`.
    var name: String
    var form: Form
    var format: Format
    var padding: Padding
    /// The ciphertext's length, recorded.
    var encryptedLength: Int

    var testDescription: String {
        name
    }

    /// The file, from the test bundle.
    func data() throws -> Data {
        try GoldenFixture.data(named: name)
    }

    /// The backup the file holds, as the import flow has it before it asks for the password.
    func encryptedVault() throws -> EncryptedVault {
        switch form {
        case .pdf:
            let document = try #require(PDFDocument(data: data()))
            return try VaultBackupPDFDetatcherImpl().detachEncryptedVault(fromPDF: document)
        case .encryptedVault:
            return try EncryptedVaultCoder().decode(vaultData: data())
        case .qrCodes:
            let codes = try JSONDecoder().decode([String].self, from: data())
            return try EncryptedVaultCoder().decode(vaultData: TransferQRCodes.join(codes))
        }
    }

    /// The items restoring it gives back: the vault it was made of, as its format carried it.
    func restoredItems() throws -> [VaultItem] {
        try BackupCorpus.sourceItems().map { item in
            var item = item
            switch format {
            case .current:
                break
            case .beforeQuickTypeAndPreview:
                item.metadata.showInQuickType = true
                item.metadata.previewMode = .titleAndFirstLine
            case .plaintextSearchPassphrase:
                item.metadata.showInQuickType = true
                item.metadata.previewMode = .titleAndFirstLine
                item.metadata.searchPassphrase = nil
            }
            return item
        }
    }
}

extension BackupCorpusEntry {
    /// A PDF backup as the Backups page saved one from #624 until VAULT-75: v2.0.0 builds 100008 to 100011.
    static let pdfWithRandomPadding = BackupCorpusEntry(
        name: "Backups/pdf-random-padding.pdf",
        form: .pdf,
        format: .current,
        padding: .random,
        encryptedLength: 3216,
    )

    /// A PDF backup as the Backups page saved one before #624: v2.0.0 build 100007 and earlier, back to #519.
    static let pdfBeforeQuickTypeAndPreview = BackupCorpusEntry(
        name: "Backups/pdf-before-quicktype-and-preview.pdf",
        form: .pdf,
        format: .beforeQuickTypeAndPreview,
        padding: .random,
        encryptedLength: 5160,
    )

    /// A PDF backup as the Backups page saved one before #519, with search passphrases in plain text.
    static let pdfWithPlaintextSearchPassphrase = BackupCorpusEntry(
        name: "Backups/pdf-plaintext-search-passphrase.pdf",
        form: .pdf,
        format: .plaintextSearchPassphrase,
        padding: .random,
        encryptedLength: 4076,
    )

    /// An auto-backup as `AutoBackupServiceImpl` saves one, padded to its fixed size: the backup its PDF carries.
    ///
    /// The corpus keeps the backup rather than the PDF. A PDF around a backup padded to 32 KiB is about a megabyte,
    /// most of it the images of its 90 or so QR codes, and the other PDFs cover reading a backup out of one. It stands
    /// for the Backups page's PDFs since VAULT-75 too, whose backups are the same.
    static let autoBackup = BackupCorpusEntry(
        name: "Backups/auto-backup.json",
        form: .encryptedVault,
        format: .current,
        padding: .toFixedSize,
        encryptedLength: 32764,
    )

    /// The backups restored from a file.
    static let backups = [
        autoBackup,
        pdfWithRandomPadding,
        pdfBeforeQuickTypeAndPreview,
        pdfWithPlaintextSearchPassphrase,
    ]

    /// The QR codes a device transfer shows (`DeviceTransferExportViewModel`).
    static let transferQRCodes = BackupCorpusEntry(
        name: "Backups/transfer-qr-codes.json",
        form: .qrCodes,
        format: .current,
        padding: .random,
        encryptedLength: 2832,
    )
}

// MARK: - The vault

/// The vault every backup in the corpus was made of.
enum BackupCorpus {
    /// Every backup's password.
    static let password = "correct horse battery staple"
    /// When every backup was made. A whole number of milliseconds, which is how a backup stores it.
    static let created = Date(timeIntervalSince1970: 1_790_000_000)

    /// The killphrase and search passphrase keys of the device the backups were made on. Each item's digests are made
    /// with them, so the phrases work only where those keys are.
    static let killphraseKey = KeyData<32>.repeating(byte: 0xA1)
    static let searchPassphraseKey = KeyData<32>.repeating(byte: 0xA2)
    static let killphrase = "kill me"
    static let searchPassphrase = "find me"

    static let tags = [
        VaultItemTag(
            id: Identifier(id: UUID(uuidString: "A8582716-0C09-475A-9295-A3C0F0E67251")!),
            name: "Personal",
            color: VaultItemColor(red: 0.2, green: 0.5, blue: 0.9),
            iconName: "person.fill",
        ),
        VaultItemTag(id: Identifier(id: UUID(uuidString: "B349F093-958A-440D-BEA8-E1231E281A5A")!), name: "Work"),
    ]

    /// The vault's items: two codes, a note that's hidden behind a search passphrase, and the two encrypted item
    /// fixtures, whose own passwords open them after a restore.
    static func sourceItems() throws -> [VaultItem] {
        try plainItems + [EncryptedItemFixture.note.storedItem(), EncryptedItemFixture.recoveryPhrase.storedItem()]
    }

    static let plainItems = [
        VaultItem(
            metadata: metadata(
                id: "ED314A19-B48C-430A-B280-6540D860542C",
                relativeOrder: 0,
                userDescription: "Personal email",
                tags: [tags[0].id],
                color: VaultItemColor(red: 0.9, green: 0.3, blue: 0.1),
                showInQuickType: false,
            ),
            item: .otpCode(OTPAuthCode(
                type: .totp(period: 30),
                data: OTPAuthCodeData(
                    secret: OTPAuthSecret(data: Data("12345678901234567890".utf8), format: .base32),
                    algorithm: .sha1,
                    digits: 6,
                    accountName: "alice@example.com",
                    issuer: "Example Mail",
                ),
            )),
        ),
        VaultItem(
            metadata: metadata(
                id: "C0CF4EE1-08AC-480E-AB5C-DE74624F1D5D",
                relativeOrder: 10,
                tags: [tags[1].id],
                searchableLevel: .onlyTitle,
                // `killphrase`, with `killphraseKey`.
                killphrase: KillphraseDigest(
                    salt: Data(hex: "6b1f0e3a9c2d4e8f7a5b3c1d0e2f4a6b"),
                    digest: Data(hex: "ab03f85c3194a88b5248352dce9756e15a28a4daf099613fab5bbf04f07d42f5"),
                ),
                previewMode: .titleOnly,
            ),
            item: .otpCode(OTPAuthCode(
                type: .hotp(counter: 42),
                data: OTPAuthCodeData(
                    secret: OTPAuthSecret(data: Data("a bank's hotp secret".utf8), format: .base32),
                    algorithm: .sha256,
                    digits: 8,
                    accountName: "alice",
                    issuer: "Example Bank",
                ),
            )),
        ),
        VaultItem(
            metadata: metadata(
                id: "4DF9A6D8-E53D-448E-800A-5320F415A9DE",
                relativeOrder: 20,
                tags: [tags[0].id, tags[1].id],
                visibility: .onlySearch,
                searchableLevel: .onlyPassphrase,
                // `searchPassphrase`, with `searchPassphraseKey`.
                searchPassphrase: SearchPassphraseDigest(
                    salt: Data(hex: "2c4e6a8b0d1f3e5a7c9b1d3f5e7a9c0b"),
                    digest: Data(hex: "a95cd35dd874ba7a1a62e64274610da9d8e91604f02e392811873b1e64eb1d26"),
                ),
                lockState: .lockedWithNativeSecurity,
                previewMode: .hidden,
            ),
            item: .secureNote(SecureNote(
                title: "Travel plans",
                contents: "# Itinerary\n\n- Fly out on the 3rd\n- Hotel booking **QX-4471**",
                format: .markdown,
            )),
        ),
    ]

    private static func metadata(
        id: String,
        relativeOrder: UInt64,
        userDescription: String = "",
        tags: Set<Identifier<VaultItemTag>> = [],
        visibility: VaultItemVisibility = .always,
        searchableLevel: VaultItemSearchableLevel = .full,
        searchPassphrase: SearchPassphraseDigest? = nil,
        killphrase: KillphraseDigest? = nil,
        lockState: VaultItemLockState = .notLocked,
        color: VaultItemColor? = nil,
        showInQuickType: Bool = true,
        previewMode: NotePreviewMode = .titleAndFirstLine,
    ) -> VaultItem.Metadata {
        VaultItem.Metadata(
            id: Identifier(id: UUID(uuidString: id)!),
            created: Date(timeIntervalSince1970: 1_760_000_000 + TimeInterval(relativeOrder)),
            updated: Date(timeIntervalSince1970: 1_770_000_000 + TimeInterval(relativeOrder)),
            relativeOrder: relativeOrder,
            userDescription: userDescription,
            tags: tags,
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphrase: searchPassphrase,
            killphrase: killphrase,
            lockState: lockState,
            color: color,
            showInQuickType: showInQuickType,
            previewMode: previewMode,
        )
    }
}

// MARK: - Restoring

/// A vault as the app has it while it restores a backup: a store behind the store session, and the data model the
/// import flow imports into.
@MainActor
struct RestoreHarness {
    let session: VaultStoreSession
    let dataModel: VaultDataModel

    init(session: VaultStoreSession) {
        self.session = session
        dataModel = VaultDataModel(
            vaultStore: session,
            vaultTagStore: session,
            vaultImporter: session,
            vaultDeleter: session,
            vaultKillphraseDeleter: session,
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: StubKillphraseKeyStore(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        )
    }

    /// A new, empty plain store: SwiftData, in memory.
    static func plain() throws -> RestoreHarness {
        let container = try ModelContainer(
            for: PersistedVaultItem.self, PersistedVaultTag.self,
            configurations: .init(isStoredInMemoryOnly: true),
        )
        return RestoreHarness(
            session: VaultStoreSession(target: .plain(PersistedLocalVaultStore(modelContainer: container))),
        )
    }

    /// Restores a backup from the corpus with its password: a PDF from the file, and the auto-backup's backup, which
    /// the corpus keeps without its PDF, from where the import flow has read it out of the PDF.
    func restore(_ entry: BackupCorpusEntry, context: BackupImportContext = .merge) async throws {
        switch entry.form {
        case .pdf:
            try await restore(pdf: entry.data(), password: BackupCorpus.password, context: context)
        case .encryptedVault, .qrCodes:
            try await restore(encryptedVault: entry.encryptedVault(), password: BackupCorpus.password, context: context)
        }
    }

    /// Restores a PDF as the Backups page does: the import flow detaches the backup and asks for its password, the
    /// password decrypts it in the password screen (`BackupKeyDecryptorViewModel`), and the flow imports it.
    func restore(pdf: Data, password: String, context: BackupImportContext = .merge) async throws {
        let flow = makeImportFlow(context: context)
        await flow.handleImport(fromPDF: .success(pdf))
        try await finish(flow, password: password)
    }

    /// Restores a backup the import flow already has: scanned from QR codes, or read out of a PDF.
    func restore(encryptedVault vault: EncryptedVault, password: String, context: BackupImportContext = .merge)
        async throws
    {
        let flow = makeImportFlow(context: context)
        await flow.handleImport(fromEncryptedVault: vault)
        try await finish(flow, password: password)
    }

    /// The import flow, which always asks for the backup's password.
    func makeImportFlow(context: BackupImportContext) -> BackupImportFlowViewModel {
        BackupImportFlowViewModel(
            importContext: context,
            dataModel: dataModel,
            existingBackupPassword: nil,
            encryptedVaultDecoder: EncryptedVaultDecoderImpl(),
        )
    }

    /// Enters the password when the flow asks for it, then imports what it decrypts.
    private func finish(_ flow: BackupImportFlowViewModel, password: String) async throws {
        guard case let .needsPasswordEntry(encryptedVault) = flow.payloadState else {
            Issue.record("Expected the flow to ask for the password, got \(flow.payloadState)")
            return
        }
        let decrypted = PassthroughSubject<VaultApplicationPayload, Never>()
        var received: VaultApplicationPayload?
        let subscription = decrypted.sink { received = $0 }
        defer { subscription.cancel() }
        let passwordScreen = BackupKeyDecryptorViewModel(
            encryptedVault: encryptedVault,
            keyDeriverFactory: VaultKeyDeriverFactoryImpl(),
            encryptedVaultDecoder: EncryptedVaultDecoderImpl(),
            decryptedVaultSubject: decrypted,
        )
        passwordScreen.enteredPassword = password
        await passwordScreen.attemptDecryption()
        #expect(passwordScreen.decryptionKeyState == .validDecryptionKey)
        try flow.handleVaultDecoded(payload: #require(received))
        guard case let .ready(payload, _) = flow.payloadState else {
            Issue.record("Expected a payload ready to import, got \(flow.payloadState)")
            return
        }
        await flow.importPayload(payload: payload)
        #expect(flow.importState == .success)
    }

    /// Everything the open vault holds, hidden items included, sorted by id.
    func vault() async throws -> (items: [VaultItem], tags: [VaultItemTag]) {
        let export = try await session.exportVault(userDescription: "")
        return (export.items.sorted { $0.id.id.uuidString < $1.id.id.uuidString }, export.tags)
    }
}

extension [VaultItem] {
    /// Sorted by id, as `RestoreHarness.vault()` returns them.
    var sortedByID: [VaultItem] {
        sorted { $0.id.id.uuidString < $1.id.id.uuidString }
    }
}
