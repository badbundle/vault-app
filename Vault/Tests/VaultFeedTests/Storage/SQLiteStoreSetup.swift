import Foundation
import SwiftData
import Testing
@testable import VaultFeed

/// The ways the SwiftData store is opened on a SQLite file, for tests that need a real file.
enum SQLiteStoreSetup: CaseIterable, Sendable, CustomTestStringConvertible {
    /// Opened by `PersistedLocalVaultStoreFactory` as the app opens it: `vault-primary.sqlite`, with the
    /// migration plan.
    case app
    /// `VaultStoreEngine.swiftDataSQLite`, the contract suite's SQLite store.
    case contractEngine

    var testDescription: String {
        switch self {
        case .app: "app"
        case .contractEngine: "contract engine"
        }
    }

    /// A new, empty store, and the URL of its SQLite file.
    func makeStore() async throws -> (PersistedLocalVaultStore, URL) {
        switch self {
        case .app:
            let directory = URL.temporaryDirectory.appending(path: "store-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
            return (store, directory.appending(path: "vault-primary.sqlite"))
        case .contractEngine:
            let engineStore = try await VaultStoreEngine.swiftDataSQLite.makeStore()
            let store = try #require(engineStore as? PersistedLocalVaultStore)
            let storeURL = await store.storeURL
            return try (store, #require(storeURL))
        }
    }

    /// A second store on the same file.
    func reopenStore(at storeURL: URL) throws -> PersistedLocalVaultStore {
        try PersistedLocalVaultStore(modelContainer: makeContainer(storeURL: storeURL))
    }

    /// Deletes every item through a separate SwiftData container, as an earlier session that never scrubbed
    /// would have.
    func deleteAllItemsWithoutScrubbing(storeURL: URL) throws {
        let context = try ModelContext(makeContainer(storeURL: storeURL))
        try context.delete(model: PersistedVaultItem.self)
        try context.save()
    }

    /// Deletes the store's directory and everything in it.
    static func removeStore(at storeURL: URL) {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }

    private func makeContainer(storeURL: URL) throws -> ModelContainer {
        switch self {
        case .app:
            try ModelContainer(
                for: PersistedVaultItem.self, PersistedVaultTag.self,
                migrationPlan: PersistedSchemaMigrationPlan.self,
                configurations: ModelConfiguration(
                    "PersistedLocalVaultStore",
                    schema: .init(versionedSchema: PersistedSchemaLatestVersion.self),
                    url: storeURL,
                ),
            )
        case .contractEngine:
            try ModelContainer(for: PersistedVaultItem.self, configurations: .init(url: storeURL))
        }
    }
}
