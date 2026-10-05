import Combine
import Foundation
import FoundationExtensions
import ImageIO
import PDFKit
import Testing
import VaultBackup
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// Restoring every backup in the corpus, as the Backups page does: the PDF into the import flow, its password into the
/// password screen, and what it decrypts into the vault. The auto-backup, which the corpus keeps without its PDF, goes
/// into the flow from where the flow has read it out of the PDF. See `Fixtures/Backups/README.md`.
struct BackupCorpusRestoreTests {
    /// Every item arrives as the backup carried it: its killphrase and search passphrase digests, its lock state, and,
    /// if it's encrypted, its encryption, which its own password still opens. On the device that made the backup, with
    /// its keys, the killphrase deletes its item and the search passphrase finds its hidden note, as before. A backup
    /// from before #519 carried its search passphrase in plain text, and restoring it drops it, so there it finds
    /// nothing.
    @MainActor
    @Test(arguments: BackupCorpusEntry.backups)
    func backup_restoresToExactlyTheVaultItWasMadeOf(entry: BackupCorpusEntry) async throws {
        let harness = try RestoreHarness.plain()

        try await harness.restore(entry)

        let vault = try await harness.vault()
        #expect(try vault.items == entry.restoredItems().sortedByID)
        #expect(Set(vault.tags) == Set(BackupCorpus.tags))
        for fixture in EncryptedItemFixture.all {
            let restored = try #require(vault.items.first { $0.id == fixture.metadata.id })
            let encrypted = try #require(restored.item.encryptedItem)
            #expect(try EncryptedItemFixture.decrypt(encrypted, password: fixture.password) == fixture.decrypted)
        }
        let found = try await harness.session.retrieve(
            query: .init(filterText: BackupCorpus.searchPassphrase),
            searchPassphraseMatcher: SearchPassphraseDigester(key: BackupCorpus.searchPassphraseKey),
        )
        #expect(found.items.map(\.id)
            .contains(BackupCorpus.plainItems[2].id) == (entry.format != .plaintextSearchPassphrase))
        let deleted = await harness.session.deleteItems(
            matchingKillphrase: BackupCorpus.killphrase,
            using: KillphraseDigester(key: BackupCorpus.killphraseKey),
        )
        #expect(deleted)
        #expect(try await !harness.vault().items.map(\.id).contains(BackupCorpus.plainItems[1].id))
    }

    @Test(arguments: BackupCorpusEntry.backups + [.transferQRCodes])
    func backup_isPaddedAsItsFormatWas(entry: BackupCorpusEntry) throws {
        let vault = try entry.encryptedVault()

        #expect(vault.version == "1.0.0")
        #expect(vault.keygenSignature == VaultKeyDeriver.Signature.backupFastV1.rawValue)
        #expect(vault.data.count == entry.encryptedLength)
        switch entry.padding {
        case .toFixedSize: #expect((32 * 1024 - 16 ... 32 * 1024).contains(vault.data.count))
        case .random: #expect(vault.data.count < 32 * 1024 - 16)
        }
    }

    /// A printed backup holds the whole backup in its QR codes, as scanning the paper reads them, whichever device made
    /// it: the Mac's PDF, drawn by its own renderer, as well as the iPhone's.
    @Test(arguments: BackupCorpusEntry.pdfs)
    func pdf_qrCodes_holdExactlyTheBackupItCarries(entry: BackupCorpusEntry) throws {
        let document = try #require(PDFDocument(data: entry.data()))

        let codes = try (0 ..< document.pageCount).flatMap { try PrintedQRCodes.read(page: $0, of: document) }

        let scanned = try EncryptedVaultCoder().decode(vaultData: TransferQRCodes.join(codes))
        #expect(try scanned == entry.encryptedVault())
    }

    @MainActor
    @Test
    func pdf_withAWrongPassword_restoresNothing() async throws {
        let harness = try RestoreHarness.plain()
        let flow = harness.makeImportFlow(context: .merge)
        try await flow.handleImport(fromPDF: .success(BackupCorpusEntry.pdfWithRandomPadding.data()))
        guard case let .needsPasswordEntry(encryptedVault) = flow.payloadState else {
            Issue.record("Expected the flow to ask for the password, got \(flow.payloadState)")
            return
        }
        let passwordScreen = BackupKeyDecryptorViewModel(
            encryptedVault: encryptedVault,
            keyDeriverFactory: VaultKeyDeriverFactoryImpl(),
            encryptedVaultDecoder: EncryptedVaultDecoderImpl(),
            decryptedVaultSubject: PassthroughSubject(),
        )
        passwordScreen.enteredPassword = BackupCorpus.password.uppercased()

        await passwordScreen.attemptDecryption()

        #expect(passwordScreen.decryptionKeyState.isError)
        #expect(try await harness.vault().items.isEmpty)
    }

    /// Restored on another device, whose killphrase and search passphrase keys differ from the ones the backup's
    /// digests were made with, the backup still imports, and every item arrives with its killphrase and search
    /// passphrase digests, and its lock state, exactly as the backup carried them.
    @MainActor
    @Test
    func pdf_onAnotherDevice_importsTheItemsWithTheirDigestsAsTheyWere() async throws {
        let entry = BackupCorpusEntry.pdfWithRandomPadding
        let otherDevice = KillphraseDigester(key: .zero())
        let harness = try RestoreHarness.plain()

        try await harness.restore(pdf: entry.data(), password: BackupCorpus.password)

        let restored = try await harness.vault().items
        let expected = try entry.restoredItems().sortedByID
        #expect(BackupCorpus.killphraseKey != .zero())
        #expect(try !otherDevice.matches(
            query: BackupCorpus.killphrase,
            salt: #require(BackupCorpus.plainItems[1].metadata.killphrase).salt,
            digest: #require(BackupCorpus.plainItems[1].metadata.killphrase).digest,
        ))
        #expect(restored.map(\.metadata.killphrase) == expected.map(\.metadata.killphrase))
        #expect(restored.map(\.metadata.searchPassphrase) == expected.map(\.metadata.searchPassphrase))
        #expect(restored.map(\.metadata.lockState) == expected.map(\.metadata.lockState))
    }

    @MainActor
    @Test
    func pdf_override_replacesWhatTheVaultHeld() async throws {
        let harness = try RestoreHarness.plain()
        try await harness.session.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [uniqueVaultItem()],
            tags: [anyVaultItemTag()],
        ))

        try await harness.restore(
            pdf: BackupCorpusEntry.pdfWithRandomPadding.data(),
            password: BackupCorpus.password,
            context: .override,
        )

        let vault = try await harness.vault()
        #expect(try vault.items == BackupCorpusEntry.pdfWithRandomPadding.restoredItems().sortedByID)
        #expect(Set(vault.tags) == Set(BackupCorpus.tags))
    }

    @MainActor
    @Test
    func pdf_merge_keepsWhatTheVaultHeld() async throws {
        let harness = try RestoreHarness.plain()
        let existing = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 1_700_000_000))
        try await harness.session.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [existing],
            tags: [],
        ))

        try await harness.restore(
            pdf: BackupCorpusEntry.pdfWithRandomPadding.data(),
            password: BackupCorpus.password,
            context: .merge,
        )

        #expect(try await harness.vault().items == (BackupCorpusEntry.pdfWithRandomPadding.restoredItems() + [existing])
            .sortedByID)
    }
}

// MARK: - Into an encrypted vault

extension BackupCorpusRestoreTests {
    /// Restored into a vault the App Lock Password encrypts, the items are saved to its slot: opened again from the
    /// file on disk with the password, they're there.
    @MainActor
    @Test
    func pdf_intoAnEncryptedVault_isThereWhenItsOpenedAgainFromDisk() async throws {
        try await withTemporaryDirectory { directory in
            let file = EncryptedVaultFile(directory: directory)
            var contents = try VaultSlotFile(kdfParameters: SlotFileFixture.kdfParameters)
            let slot = try contents.createVault(
                inSlot: 3,
                rootKey: contents.header.passwordKey(for: "app lock password"),
                payload: EncryptedVaultPayload.encode(.empty),
                wrappedAt: Date(timeIntervalSince1970: 1_790_000_000),
            )
            try contents.bytes.write(to: file.url)
            let store = EncryptedVaultStore(file: file, slot: slot, state: .empty)
            let harness = RestoreHarness(session: VaultStoreSession(target: .unlocked(store)))

            try await harness.restore(
                pdf: BackupCorpusEntry.pdfWithRandomPadding.data(),
                password: BackupCorpus.password,
            )

            let reopened = try VaultSlotFile(bytes: Data(contentsOf: file.url))
            let key = try reopened.header.passwordKey(for: "app lock password")
            let opened = VaultSlotFile.slotIndices.compactMap { try? reopened.openSlot($0, with: key) }
            #expect(opened.map(\.index) == [3])
            let state = try EncryptedVaultPayload.decode(slot: #require(opened.first), in: reopened)
            let decoder = PersistedVaultItemDecoder()
            #expect(try state.items.map(decoder.decode(record:)).sortedByID == BackupCorpusEntry.pdfWithRandomPadding
                .restoredItems()
                .sortedByID)
        }
    }

    /// Restored into a duress vault, only the duress vault's slot changes. The real vault keeps its items and its own
    /// backup settings (VAULT-70), byte for byte.
    @MainActor
    @Test
    func pdf_intoADuressVault_changesOnlyItsSlot() async throws {
        try await withTemporaryDirectory { directory in
            let file = EncryptedVaultFile(directory: directory)
            var contents = try VaultSlotFile(kdfParameters: SlotFileFixture.kdfParameters)
            var realState = try EncryptedVaultStoreTests.state(items: [uniqueVaultItem(), uniqueVaultItem()])
            realState.vault = VaultMetadata(
                duressSlots: VaultDuressSlots.forFirstVault(inSlot: 6),
                settings: anyVaultBackupSettings(),
            )
            let realSlot = try contents.createVault(
                inSlot: 6,
                rootKey: contents.header.passwordKey(for: "real"),
                payload: EncryptedVaultPayload.encode(realState),
                wrappedAt: Date(timeIntervalSince1970: 1_790_000_000),
            )
            try contents.bytes.write(to: file.url)
            let realStore = EncryptedVaultStore(
                file: file,
                slot: realSlot,
                state: realState,
                wrapStamper: VaultDeviceWrapStamper.inMemory { Date(timeIntervalSince1970: 1_790_000_060) },
            )
            try await realStore.makeDuressVault(password: "duress")
            let before = try VaultSlotFile(bytes: Data(contentsOf: file.url))
            let duressIndex = realState.vault.duressSlots[0]
            let duressStore = try EncryptedVaultStore(
                file: file,
                contents: before,
                slot: before.openSlot(duressIndex, with: before.header.passwordKey(for: "duress")),
            )
            let harness = RestoreHarness(session: VaultStoreSession(target: .unlocked(duressStore)))

            try await harness.restore(
                pdf: BackupCorpusEntry.pdfWithRandomPadding.data(),
                password: BackupCorpus.password,
            )

            let after = try VaultSlotFile(bytes: Data(contentsOf: file.url))
            for index in VaultSlotFile.slotIndices where index != duressIndex {
                #expect(after.bytes[after.slotRange(index)] == before.bytes[before.slotRange(index)], "slot \(index)")
            }
            let real = try after.openSlot(6, with: after.header.passwordKey(for: "real"))
            #expect(try EncryptedVaultPayload.decode(slot: real, in: after) == realState)
            let duress = try after.openSlot(duressIndex, with: after.header.passwordKey(for: "duress"))
            let decoder = PersistedVaultItemDecoder()
            #expect(try EncryptedVaultPayload.decode(slot: duress, in: after).items.map(decoder.decode(record:))
                .sortedByID == BackupCorpusEntry.pdfWithRandomPadding.restoredItems().sortedByID)
        }
    }
}

/// Reads the QR codes printed on a PDF backup's page, one by one, as a camera scanning the paper would.
///
/// Each code is drawn as an image of its own, so they're read from the page's images, as the PDF holds them: a
/// detector looking at a whole page of them, packed together, stops after a few.
enum PrintedQRCodes {
    static func read(page index: Int, of document: PDFDocument) throws -> [String] {
        let pdf = try #require(document.dataRepresentation().flatMap { CGDataProvider(data: $0 as CFData) })
        let page = try #require(CGPDFDocument(pdf)?.page(at: index + 1))
        let resources = try #require(page.dictionary.flatMap { $0.dictionary(named: "Resources") })
        return try images(in: resources).map { image in
            let png = try #require(PlatformImagePNG.data(of: image))
            return try #require(QRCodeReader.text(inPNG: png))
        }
    }

    /// The images a page's resources draw, including those inside its forms.
    private static func images(in resources: CGPDFDictionaryRef) throws -> [CGImage] {
        guard let objects = resources.dictionary(named: "XObject") else { return [] }
        var images = [CGImage]()
        var forms = [CGPDFDictionaryRef]()
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream)
            else { return true }
            switch dictionary.name(named: "Subtype") {
            case "Image":
                if let image = image(from: stream, described: dictionary) {
                    images.append(image)
                }
            case "Form":
                if let resources = dictionary.dictionary(named: "Resources") {
                    forms.append(resources)
                }
            default:
                break
            }
            return true
        }, nil)
        return try images + forms.flatMap { try self.images(in: $0) }
    }

    /// An image XObject's pixels, which the PDF keeps uncompressed once decoded: 8 bits a component, in RGB or gray.
    private static func image(from stream: CGPDFStreamRef, described dictionary: CGPDFDictionaryRef) -> CGImage? {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data?, format == .raw,
              let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        var width = 0, height = 0, bitsPerComponent = 0
        CGPDFDictionaryGetInteger(dictionary, "Width", &width)
        CGPDFDictionaryGetInteger(dictionary, "Height", &height)
        CGPDFDictionaryGetInteger(dictionary, "BitsPerComponent", &bitsPerComponent)
        guard width > 0, height > 0, bitsPerComponent == 8 else { return nil }
        let components = data.count / (width * height)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * components,
            bytesPerRow: width * components,
            space: components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent,
        )
    }
}

/// An image as PNG data, for `QRCodeReader`.
private enum PlatformImagePNG {
    static func data(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

extension CGPDFDictionaryRef {
    fileprivate func dictionary(named key: String) -> CGPDFDictionaryRef? {
        var dictionary: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(self, key, &dictionary) ? dictionary : nil
    }

    fileprivate func name(named key: String) -> String? {
        var name: UnsafePointer<CChar>?
        return CGPDFDictionaryGetName(self, key, &name) ? name.map { String(cString: $0) } : nil
    }
}
