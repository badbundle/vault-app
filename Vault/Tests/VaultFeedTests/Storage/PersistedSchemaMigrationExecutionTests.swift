import Foundation
import FoundationExtensions
import SwiftData
import Testing
@testable import VaultFeed

/// Executes the real V1 → V3 migration against an on-disk store, unlike
/// `PersistedSchemaMigrationPlanTests` which only asserts the declaration
/// shape. This is the only coverage of the `willMigrate` closures that
/// snapshot plaintext killphrases/search passphrases into the pending
/// sidecar files, and of the Phase B rehash that consumes them.
final class PersistedSchemaMigrationExecutionTests {
    private let directory: URL
    private var storeURL: URL {
        directory.appending(path: "vault-primary.sqlite")
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test
    func v1ToV3_migration_writesPendingSidecarsForNonBlankPhrases() throws {
        let protectedID = UUID()
        try seedV1Store(items: [
            .init(id: protectedID, title: "protected", killphrase: "kill me", searchPassphrase: "find me"),
            .init(id: UUID(), title: "plain", killphrase: nil, searchPassphrase: nil),
        ])

        _ = try openMigratedStore()

        let killphraseEntries = try killphraseSidecar().read()
        #expect(killphraseEntries == [.init(itemID: protectedID, phrase: "kill me")])
        let searchPassphraseEntries = try searchPassphraseSidecar().read()
        #expect(searchPassphraseEntries == [.init(itemID: protectedID, phrase: "find me")])
    }

    @Test
    func v1ToV3_migration_skipsBlankAndNilPhrases() throws {
        try seedV1Store(items: [
            .init(id: UUID(), title: "empty", killphrase: "", searchPassphrase: ""),
            .init(id: UUID(), title: "nil", killphrase: nil, searchPassphrase: nil),
        ])

        _ = try openMigratedStore()

        #expect(try killphraseSidecar().read() == [])
        #expect(try searchPassphraseSidecar().read() == [])
    }

    @Test
    func rehashServices_consumeSidecarsAndDigestsVerifyOriginalPhrases() async throws {
        let killphraseItemID = UUID()
        let hiddenItemID = UUID()
        try seedV1Store(items: [
            .init(id: killphraseItemID, title: "armed", killphrase: "kill me", searchPassphrase: nil),
            .init(
                id: hiddenItemID,
                title: "hidden",
                killphrase: nil,
                searchPassphrase: "find me",
                visibility: VaultEncodingConstants.Visibility.onlySearch,
                searchableLevel: VaultEncodingConstants.SearchableLevel.onlyPassphrase,
            ),
            .init(id: UUID(), title: "plain", killphrase: nil, searchPassphrase: nil),
        ])
        let store = try openMigratedStore()
        let killDigester = KillphraseDigester(key: .zero())
        let searchDigester = SearchPassphraseDigester(key: .zero())

        await KillphraseRehashService(storeDirectory: directory) { id, digest in
            try await store.applyKillphraseDigest(itemID: id, digest: digest)
        }.run(using: killDigester)
        await SearchPassphraseRehashService(storeDirectory: directory) { id, digest in
            try await store.applySearchPassphraseDigest(itemID: id, digest: digest)
        }.run(using: searchDigester)

        // Sidecars are consumed (securely cleared) once every entry has
        // been written back as a digest.
        #expect(try killphraseSidecar().read() == [])
        #expect(try searchPassphraseSidecar().read() == [])

        // Behavioral digest proof for the killphrase: deletion fires with
        // the original phrase. This is the only public observation point
        // for killphrase digests — deliberate, MANIFESTO C5.
        let didDelete = await store.deleteItems(matchingKillphrase: "kill me", using: killDigester)
        #expect(didDelete == true)

        // Behavioral proof for the search passphrase: the hidden item is
        // reachable only through a matching digest.
        let withoutMatcher = try await store.retrieve(query: .init(filterText: "find me"))
        #expect(withoutMatcher.items.map(\.id.rawValue).contains(hiddenItemID) == false)
        let withMatcher = try await store.retrieve(
            query: .init(filterText: "find me"),
            searchPassphraseMatcher: searchDigester,
        )
        #expect(withMatcher.items.map(\.id.rawValue).contains(hiddenItemID))
        #expect(withMatcher.errors.isEmpty)
    }

    @Test
    func rehashServices_idempotentWhenSidecarMissing() async throws {
        try seedV1Store(items: [
            .init(id: UUID(), title: "plain", killphrase: nil, searchPassphrase: nil),
        ])
        _ = try openMigratedStore()

        await confirmation("Writer never called", expectedCount: 0) { confirmWrite in
            await KillphraseRehashService(storeDirectory: directory) { _, _ in
                confirmWrite()
            }.run(using: KillphraseDigester(key: .zero()))
        }
    }
}

// MARK: - Helpers

extension PersistedSchemaMigrationExecutionTests {
    private struct V1Item {
        let id: UUID
        let title: String
        let killphrase: String?
        let searchPassphrase: String?
        var visibility = VaultEncodingConstants.Visibility.always
        var searchableLevel = VaultEncodingConstants.SearchableLevel.full

        init(
            id: UUID,
            title: String,
            killphrase: String?,
            searchPassphrase: String?,
            visibility: String = VaultEncodingConstants.Visibility.always,
            searchableLevel: String = VaultEncodingConstants.SearchableLevel.full,
        ) {
            self.id = id
            self.title = title
            self.killphrase = killphrase
            self.searchPassphrase = searchPassphrase
            self.visibility = visibility
            self.searchableLevel = searchableLevel
        }
    }

    /// Builds an on-disk V1 store and releases the container so the
    /// migrated reopen has exclusive access.
    private func seedV1Store(items: [V1Item]) throws {
        let configuration = ModelConfiguration(
            "PersistedLocalVaultStore",
            schema: Schema(versionedSchema: PersistedSchemaV1.self),
            url: storeURL,
        )
        let container = try ModelContainer(
            for: Schema(versionedSchema: PersistedSchemaV1.self),
            configurations: configuration,
        )
        let context = ModelContext(container)
        for item in items {
            context.insert(PersistedSchemaV1.PersistedVaultItem(
                id: item.id,
                relativeOrder: 0,
                createdDate: Date(),
                updatedDate: Date(),
                userDescription: item.title,
                visibility: item.visibility,
                searchableLevel: item.searchableLevel,
                searchPassphrase: item.searchPassphrase,
                killphrase: item.killphrase,
                lockState: nil,
                color: nil,
                showInQuickType: true,
                previewMode: NotePreviewMode.titleAndFirstLine.rawValue,
                tags: [],
                noteDetails: PersistedSchemaV1.PersistedNoteDetails(
                    title: item.title,
                    contents: "contents",
                    format: VaultEncodingConstants.TextFormat.plain,
                ),
                otpDetails: nil,
                encryptedItemDetails: nil,
            ))
        }
        try context.save()
    }

    /// Reopens the store through the real migration plan, exactly as the
    /// production `SwiftDataPersistedLocalVaultStoreOpener` does. Custom
    /// migration stages run synchronously during container init.
    private func openMigratedStore() throws -> PersistedLocalVaultStore {
        let configuration = ModelConfiguration(
            "PersistedLocalVaultStore",
            schema: Schema(versionedSchema: PersistedSchemaLatestVersion.self),
            url: storeURL,
        )
        let container = try ModelContainer(
            for: PersistedVaultItem.self, PersistedVaultTag.self,
            migrationPlan: PersistedSchemaMigrationPlan.self,
            configurations: configuration,
        )
        return PersistedLocalVaultStore(modelContainer: container)
    }

    private func killphraseSidecar() -> PendingKillphraseRehashStore {
        PendingKillphraseRehashStore(fileURL: PendingKillphraseRehashStore.defaultURL(storeDirectory: directory))
    }

    private func searchPassphraseSidecar() -> PendingSearchPassphraseRehashStore {
        PendingSearchPassphraseRehashStore(
            fileURL: PendingSearchPassphraseRehashStore.defaultURL(storeDirectory: directory),
        )
    }
}
