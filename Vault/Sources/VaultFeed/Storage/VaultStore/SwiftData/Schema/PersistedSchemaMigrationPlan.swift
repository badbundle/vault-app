import Foundation
import SwiftData

enum PersistedSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PersistedSchemaV1.self, PersistedSchemaV2.self, PersistedSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3]
    }

    /// V1 → V2 swaps plaintext `killphrase` for the salted-HMAC pair
    /// `(killphraseSalt, killphraseDigest)`.
    ///
    /// The HMAC key is derived from the user's vault key, which is not
    /// available at migration time (the user has not yet unlocked). So the
    /// migration runs in two phases:
    ///
    /// 1. **`willMigrate`** — snapshots every `(itemID, plaintext)` pair
    ///    where `killphrase` was non-`nil` into a sibling file with file
    ///    protection. The plaintext field is then dropped by SwiftData as
    ///    part of the schema swap to V2.
    /// 2. **`didMigrate`** — no-op here: the rehash is performed later by
    ///    `KillphraseRehashService.run(digester:)` once the user unlocks
    ///    the vault for the first time after upgrading.
    ///
    /// The window between Phase 1 and Phase 2 is the only time plaintext
    /// killphrases live outside the SwiftData store. The rehash service
    /// deletes the pending file once it's done, and the app scrubs the
    /// dropped column's pages out of the store's files at launch
    /// (`PersistedLocalVaultStore.scrubContentLeftByEarlierSessions()`).
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: PersistedSchemaV1.self,
        toVersion: PersistedSchemaV2.self,
        willMigrate: { context in
            let descriptor = FetchDescriptor<PersistedSchemaV1.PersistedVaultItem>()
            let items = try context.fetch(descriptor)
            let entries: [PendingKillphraseRehashStore.Entry] = items.compactMap { item in
                guard let phrase = item.killphrase, phrase.isEmpty == false else { return nil }
                return .init(itemID: item.id, phrase: phrase)
            }
            guard entries.isEmpty == false else { return }

            let storeURL = pendingKillphraseURL(for: context)
            let pending = PendingKillphraseRehashStore(fileURL: storeURL)
            try pending.write(entries)
        },
        didMigrate: nil,
    )

    /// V2 → V3 swaps plaintext `searchPassphrase` for the salted-HMAC pair
    /// `(searchPassphraseSalt, searchPassphraseDigest)`. Same two-phase
    /// pattern as V1 → V2: snapshot plaintext in `willMigrate`, rehash on
    /// first post-upgrade unlock via `SearchPassphraseRehashService`.
    static let v2ToV3 = MigrationStage.custom(
        fromVersion: PersistedSchemaV2.self,
        toVersion: PersistedSchemaV3.self,
        willMigrate: { context in
            let descriptor = FetchDescriptor<PersistedSchemaV2.PersistedVaultItem>()
            let items = try context.fetch(descriptor)
            let entries: [PendingSearchPassphraseRehashStore.Entry] = items.compactMap { item in
                guard let phrase = item.searchPassphrase, phrase.isEmpty == false else { return nil }
                return .init(itemID: item.id, phrase: phrase)
            }
            guard entries.isEmpty == false else { return }

            let storeURL = pendingSearchPassphraseURL(for: context)
            let pending = PendingSearchPassphraseRehashStore(fileURL: storeURL)
            try pending.write(entries)
        },
        didMigrate: nil,
    )

    private static func pendingKillphraseURL(for context: ModelContext) -> URL {
        PendingKillphraseRehashStore.defaultURL(storeDirectory: storeDirectory(for: context))
    }

    private static func pendingSearchPassphraseURL(for context: ModelContext) -> URL {
        PendingSearchPassphraseRehashStore.defaultURL(storeDirectory: storeDirectory(for: context))
    }

    /// Best-effort lookup of the directory containing the SwiftData store,
    /// so the pending-rehash file can live alongside it.
    private static func storeDirectory(for context: ModelContext) -> URL {
        if let configURL = context.container.configurations.first?.url {
            configURL.deletingLastPathComponent()
        } else {
            URL.applicationSupportDirectory
        }
    }
}
