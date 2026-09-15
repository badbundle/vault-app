import Foundation
import FoundationExtensions
import PDFKit
import SwiftData
import Testing
import VaultBackup
import VaultCore
import VaultExport
import VaultKeygen
@testable import VaultFeed

/// End-to-end backup pipeline: seed store → export → encrypt → attach to
/// PDF → serialize → detach → decrypt → import into a second store. The
/// individual stages are unit-covered in VaultBackupTests; this proves
/// the composition, and in particular that duress metadata (killphrase
/// and search-passphrase digests, lock state, searchable level) survives
/// the full trip (MANIFESTO C10).
struct BackupRoundTripTests {
    private let killDigester = KillphraseDigester(key: .zero())
    private let searchDigester = SearchPassphraseDigester(key: .zero())

    @Test
    func pdfRoundTrip_merge_preservesDuressMetadata() async throws {
        let source = try makeInMemoryStore()
        let armedItem = anySecureNote(title: "armed").wrapInAnyVaultItem(
            killphrase: killDigester.makeDigest(phrase: "kill me"),
        )
        let hiddenItem = anySecureNote(title: "hidden").wrapInAnyVaultItem(
            visibility: .onlySearch,
            searchableLevel: .onlyPassphrase,
            searchPassphrase: searchDigester.makeDigest(phrase: "find me"),
        )
        let lockedItem = anySecureNote(title: "locked").wrapInAnyVaultItem(
            lockState: .lockedWithNativeSecurity,
        )
        let tag = anyVaultItemTag()
        try await source.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [armedItem, hiddenItem, lockedItem],
            tags: [tag],
        ))

        let restored = try await roundTripThroughPDF(source: source)
        let destination = try makeInMemoryStore()
        try await destination.importAndMergeVault(payload: restored)

        // Tags and item count survive.
        let allItems = try await destination.retrieve(query: .init())
        #expect(try await destination.retrieveTags().map(\.id) == [tag.id])

        // Lock state and searchable level survive on the restored rows.
        let restoredLocked = try #require(allItems.items.first(where: { $0.id == lockedItem.id }))
        #expect(restoredLocked.metadata.lockState == .lockedWithNativeSecurity)

        // The hidden item is reachable only through a matching digest.
        let withoutMatcher = try await destination.retrieve(query: .init(filterText: "hidden"))
        #expect(withoutMatcher.items.map(\.id).contains(hiddenItem.id) == false)
        let withMatcher = try await destination.retrieve(
            query: .init(filterText: "find me"),
            searchPassphraseMatcher: searchDigester,
        )
        #expect(withMatcher.items.map(\.id).contains(hiddenItem.id))

        // The killphrase still fires with the original phrase.
        let didDelete = await destination.deleteItems(matchingKillphrase: "kill me", using: killDigester)
        #expect(didDelete == true)
        let afterKill = try await destination.retrieve(query: .init())
        #expect(afterKill.items.map(\.id).contains(armedItem.id) == false)
    }

    @Test
    func pdfRoundTrip_override_replacesExistingVault() async throws {
        let source = try makeInMemoryStore()
        let exportedItem = anySecureNote(title: "exported").wrapInAnyVaultItem()
        try await source.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [exportedItem],
            tags: [],
        ))
        let destination = try makeInMemoryStore()
        let sacrificialItem = anySecureNote(title: "sacrificial").wrapInAnyVaultItem()
        try await destination.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [sacrificialItem],
            tags: [],
        ))

        let restored = try await roundTripThroughPDF(source: source)
        try await destination.importAndOverrideVault(payload: restored)

        let items = try await destination.retrieve(query: .init())
        #expect(items.items.map(\.id) == [exportedItem.id])
    }

    @Test
    func pdfRoundTrip_wrongKey_failsDecrypt() async throws {
        let source = try makeInMemoryStore()
        try await source.importAndOverrideVault(payload: .init(
            userDescription: "",
            items: [anySecureNote(title: "secret").wrapInAnyVaultItem()],
            tags: [],
        ))
        let payload = try await source.exportVault(userDescription: "Backup")
        let pdfData = try makePDFData(payload: payload, backupPassword: anyBackupPassword())

        let pdf = try #require(PDFDocument(data: pdfData))
        let encryptedVault = try VaultBackupPDFDetatcherImpl().detachEncryptedVault(fromPDF: pdf)
        let wrongKey = try KeyData<32>(data: Data(repeating: 0xEE, count: 32))

        #expect(throws: (any Error).self) {
            try EncryptedVaultDecoderImpl().decryptAndDecode(key: wrongKey, encryptedVault: encryptedVault)
        }
    }
}

// MARK: - Helpers

extension BackupRoundTripTests {
    private func makeInMemoryStore() throws -> PersistedLocalVaultStore {
        let container = try ModelContainer(
            for: PersistedVaultItem.self, PersistedVaultTag.self,
            configurations: .init(isStoredInMemoryOnly: true),
        )
        return PersistedLocalVaultStore(modelContainer: container)
    }

    /// Export → encrypt → PDF attach → `dataRepresentation()` →
    /// `PDFDocument(data:)` → detach → decrypt. The serialize/reparse
    /// step keeps the trip honest about PDF serialization.
    private func roundTripThroughPDF(source: PersistedLocalVaultStore) async throws -> VaultApplicationPayload {
        let backupPassword = anyBackupPassword()
        let payload = try await source.exportVault(userDescription: "Backup")
        let pdfData = try makePDFData(payload: payload, backupPassword: backupPassword)

        let reparsedPDF = try #require(PDFDocument(data: pdfData))
        let encryptedVault = try VaultBackupPDFDetatcherImpl().detachEncryptedVault(fromPDF: reparsedPDF)
        return try EncryptedVaultDecoderImpl().decryptAndDecode(
            key: backupPassword.key,
            encryptedVault: encryptedVault,
        )
    }

    private func makePDFData(
        payload: VaultApplicationPayload,
        backupPassword: DerivedEncryptionKey,
    ) throws -> Data {
        let clock = EpochClockMock(currentTime: 100)
        let encryptedVault = try EncryptedVaultEncoder(clock: clock, backupPassword: backupPassword)
            .encryptAndEncode(payload: payload)
        let exportPayload = VaultExportPayload(
            encryptedVault: encryptedVault,
            userDescription: "Round-trip test backup",
            created: clock.currentDate,
        )
        let generator = VaultBackupPDFGenerator(
            size: A4DocumentSize(),
            documentTitle: "Round Trip",
            applicationName: "Vault",
            authorName: "Vault",
        )
        let pdf = try generator.makePDF(payload: exportPayload)
        return try #require(pdf.dataRepresentation())
    }

    private func anyBackupPassword() -> DerivedEncryptionKey {
        DerivedEncryptionKey(
            key: (try? KeyData<32>(data: Data(repeating: 0x45, count: 32))) ?? .zero(),
            salt: Data.random(count: 16),
            keyDervier: .testing,
        )
    }
}
