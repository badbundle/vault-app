import Foundation
import SwiftData
import Testing
@testable import VaultFeed

/// Converting plain stores written by every schema version, once the app has migrated them as it does at launch.
///
/// Each has a tagged item with a killphrase, an item hidden behind a search passphrase, and an item that doesn't
/// decode, plus an archive of an earlier store that failed to open.
struct VaultEncryptionConverterSchemaTests {
    private let killphraseDigester = KillphraseDigester(key: .zero())
    private let searchPassphraseDigester = SearchPassphraseDigester(key: .zero())

    @Test(arguments: [1, 2, 3])
    func encrypt_afterMigratingFromSchemaVersion_copiesEveryRecord(version: Int) async throws {
        try await withTemporaryDirectory { directory in
            try seed(version: version, in: directory)
            let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
            let harness = try PlainVaultConversionHarness(directory: directory, store: store)
            let archive = try VaultEncryptionConverterTests.makeArchive(in: directory)

            if version < 3 {
                // The migration left plaintext phrases to rehash: they'd outlive the conversion.
                await #expect(throws: VaultEncryptionError.pendingRehashes) {
                    try await harness.encrypt(deletingArchives: true)
                }
                try await rehash(store, in: directory)
            }
            let before = try await store.recordState()
            try await harness.encrypt(deletingArchives: true)

            let vault = try #require(try await harness.openEncryptedVault())
            #expect(before.items.count == 3)
            #expect(before.tags.count == 1)
            #expect(vault.state.items == before.items)
            #expect(vault.state.tags == before.tags)
            #expect(try !harness.fileNames().contains(archive.lastPathComponent))
            #expect(try !harness.plainStoreFilesExist())
            // The phrases still work in the encrypted vault.
            let hidden = try await harness.session.retrieve(
                query: .init(filterText: "find me"),
                searchPassphraseMatcher: searchPassphraseDigester,
            )
            #expect(hidden.items.map(\.metadata.userDescription) == ["hidden"])
            #expect(await harness.session.deleteItems(matchingKillphrase: "kill me", using: killphraseDigester))
        }
    }
}

// MARK: - Fixtures

extension VaultEncryptionConverterSchemaTests {
    private static let tagID = UUID()
    private static let armedID = UUID()
    private static let hiddenID = UUID()
    private static let brokenID = UUID()

    /// Writes a store at `version` of the schema, and closes it.
    private func seed(version: Int, in directory: URL) throws {
        let url = directory.appending(path: "vault-primary.sqlite")
        switch version {
        case 1: try seedV1(at: url)
        case 2: try seedV2(at: url)
        default: try seedV3(at: url)
        }
    }

    private func seedV1(at url: URL) throws {
        typealias V1 = PersistedSchemaV1
        let context = try Self.context(for: V1.self, at: url)
        let tag = V1.PersistedVaultTag(id: Self.tagID, title: "Work", color: nil, iconName: nil, items: [])
        context.insert(tag)
        for (id, title, killphrase, passphrase, otp) in Self.fixtureItems {
            let item = V1.PersistedVaultItem(
                id: id,
                relativeOrder: 0,
                createdDate: Date(),
                updatedDate: Date(),
                userDescription: title,
                visibility: passphrase == nil ? Self.always : Self.onlySearch,
                searchableLevel: passphrase == nil ? Self.full : Self.onlyPassphrase,
                searchPassphrase: passphrase,
                killphrase: killphrase,
                lockState: nil,
                color: nil,
                showInQuickType: true,
                previewMode: NotePreviewMode.titleAndFirstLine.rawValue,
                tags: killphrase == nil ? [] : [tag],
                noteDetails: otp ? nil : V1.PersistedNoteDetails(title: title, contents: "contents", format: "PLAIN"),
                otpDetails: otp ? V1.PersistedOTPDetails(
                    accountName: "account",
                    issuer: "issuer",
                    algorithm: Self.missingAlgorithm,
                    authType: "totp",
                    counter: nil,
                    digits: 6,
                    period: 30,
                    secretData: Data([1, 2, 3]),
                    secretFormat: "BASE_32",
                ) : nil,
                encryptedItemDetails: nil,
            )
            context.insert(item)
        }
        try context.save()
    }

    private func seedV2(at url: URL) throws {
        typealias V2 = PersistedSchemaV2
        let context = try Self.context(for: V2.self, at: url)
        let tag = V2.PersistedVaultTag(id: Self.tagID, title: "Work", color: nil, iconName: nil, items: [])
        context.insert(tag)
        for (id, title, killphrase, passphrase, otp) in Self.fixtureItems {
            let digest = killphrase.map { killphraseDigester.makeDigest(phrase: $0) }
            let item = V2.PersistedVaultItem(
                id: id,
                relativeOrder: 0,
                createdDate: Date(),
                updatedDate: Date(),
                userDescription: title,
                visibility: passphrase == nil ? Self.always : Self.onlySearch,
                searchableLevel: passphrase == nil ? Self.full : Self.onlyPassphrase,
                searchPassphrase: passphrase,
                killphraseSalt: digest?.salt,
                killphraseDigest: digest?.digest,
                lockState: nil,
                color: nil,
                showInQuickType: true,
                previewMode: NotePreviewMode.titleAndFirstLine.rawValue,
                tags: killphrase == nil ? [] : [tag],
                noteDetails: otp ? nil : V2.PersistedNoteDetails(title: title, contents: "contents", format: "PLAIN"),
                otpDetails: otp ? V2.PersistedOTPDetails(
                    accountName: "account",
                    issuer: "issuer",
                    algorithm: Self.missingAlgorithm,
                    authType: "totp",
                    counter: nil,
                    digits: 6,
                    period: 30,
                    secretData: Data([1, 2, 3]),
                    secretFormat: "BASE_32",
                ) : nil,
                encryptedItemDetails: nil,
            )
            context.insert(item)
        }
        try context.save()
    }

    private func seedV3(at url: URL) throws {
        typealias V3 = PersistedSchemaV3
        let context = try Self.context(for: V3.self, at: url)
        let tag = V3.PersistedVaultTag(id: Self.tagID, title: "Work", color: nil, iconName: nil, items: [])
        context.insert(tag)
        for (id, title, killphrase, passphrase, otp) in Self.fixtureItems {
            let killphraseDigest = killphrase.map { killphraseDigester.makeDigest(phrase: $0) }
            let passphraseDigest = passphrase.map { searchPassphraseDigester.makeDigest(phrase: $0) }
            let item = V3.PersistedVaultItem(
                id: id,
                relativeOrder: 0,
                createdDate: Date(),
                updatedDate: Date(),
                userDescription: title,
                visibility: passphrase == nil ? Self.always : Self.onlySearch,
                searchableLevel: passphrase == nil ? Self.full : Self.onlyPassphrase,
                searchPassphraseSalt: passphraseDigest?.salt,
                searchPassphraseDigest: passphraseDigest?.digest,
                killphraseSalt: killphraseDigest?.salt,
                killphraseDigest: killphraseDigest?.digest,
                lockState: nil,
                color: nil,
                showInQuickType: true,
                previewMode: NotePreviewMode.titleAndFirstLine.rawValue,
                tags: killphrase == nil ? [] : [tag],
                noteDetails: otp ? nil : V3.PersistedNoteDetails(title: title, contents: "contents", format: "PLAIN"),
                otpDetails: otp ? V3.PersistedOTPDetails(
                    accountName: "account",
                    issuer: "issuer",
                    algorithm: Self.missingAlgorithm,
                    authType: "totp",
                    counter: nil,
                    digits: 6,
                    period: 30,
                    secretData: Data([1, 2, 3]),
                    secretFormat: "BASE_32",
                ) : nil,
                encryptedItemDetails: nil,
            )
            context.insert(item)
        }
        try context.save()
    }

    /// Each item: its id, title, killphrase, search passphrase, and whether it's the OTP code that doesn't decode.
    private static var fixtureItems: [(UUID, String, String?, String?, Bool)] {
        [
            (armedID, "armed", "kill me", nil, false),
            (hiddenID, "hidden", nil, "find me", false),
            (brokenID, "broken", nil, nil, true),
        ]
    }

    /// An OTP algorithm that doesn't exist, so the item doesn't decode.
    private static let missingAlgorithm = "INVALID"

    private static let always = VaultEncodingConstants.Visibility.always
    private static let onlySearch = VaultEncodingConstants.Visibility.onlySearch
    private static let full = VaultEncodingConstants.SearchableLevel.full
    private static let onlyPassphrase = VaultEncodingConstants.SearchableLevel.onlyPassphrase

    private static func context(for schema: any VersionedSchema.Type, at url: URL) throws -> ModelContext {
        let configuration = ModelConfiguration(
            "PersistedLocalVaultStore",
            schema: Schema(versionedSchema: schema),
            url: url,
        )
        let container = try ModelContainer(for: Schema(versionedSchema: schema), configurations: configuration)
        return ModelContext(container)
    }

    /// Writes back the phrases a migration left, as the app does at launch.
    private func rehash(_ store: PersistedLocalVaultStore, in directory: URL) async throws {
        await KillphraseRehashService(storeDirectory: directory) { id, digest in
            try await store.applyKillphraseDigest(itemID: id, digest: digest)
        }.run(using: killphraseDigester)
        await SearchPassphraseRehashService(storeDirectory: directory) { id, digest in
            try await store.applySearchPassphraseDigest(itemID: id, digest: digest)
        }.run(using: searchPassphraseDigester)
    }
}
