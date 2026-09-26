import Foundation
import SwiftData
import Testing
@testable import VaultFeed

/// Converting plain stores written by every schema version, once the app has migrated them as it does at launch.
///
/// Each has a tagged note with a killphrase, a note hidden behind a search passphrase, a locked, coloured HOTP code
/// at counter 42, a password-encrypted item, and an OTP code that doesn't decode, plus an archive of an earlier
/// store that failed to open.
struct VaultEncryptionConverterSchemaTests {
    private let killphraseDigester = KillphraseDigester(key: .zero())
    private let searchPassphraseDigester = SearchPassphraseDigester(key: .zero())

    @Test(arguments: [1, 2, 3])
    func encrypt_afterMigratingFromSchemaVersion_keepsEverythingTheVaultShows(version: Int) async throws {
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
            let before = try await readEverything(from: store)
            try await harness.encrypt(deletingArchives: true)

            // Read back through the store session, as the app will, rather than comparing records with themselves.
            let after = try await readEverything(from: harness.session)
            #expect(after == before)
            #expect(before.feed.items.map(\.metadata.userDescription).sorted() == ["armed", "hotp", "sealed"])
            #expect(before.feed.errors.count == 1, "The OTP code that doesn't decode")
            #expect(before.hidden.map(\.metadata.userDescription) == ["hidden"])
            #expect(before.tags.map(\.name) == ["Work"])
            let hotp = try #require(after.feed.items.first { $0.id.rawValue == Self.hotpID })
            #expect(hotp.metadata.lockState == .lockedWithNativeSecurity)
            #expect(hotp.metadata.color == VaultItemColor(red: 0.25, green: 0.5, blue: 0.75))
            #expect(hotp.item.otpCode?.type == .hotp(counter: 42))
            #expect(after.feed.items.first { $0.id.rawValue == Self.sealedID }?.item.encryptedItem?.title == "Sealed")
            #expect(try !harness.fileNames().contains(archive.lastPathComponent))
            #expect(try !harness.plainStoreFilesExist())
            // The killphrase still works in the encrypted vault.
            #expect(await harness.session.deleteItems(matchingKillphrase: "kill me", using: killphraseDigester))
        }
    }
}

// MARK: - Reading

extension VaultEncryptionConverterSchemaTests {
    /// Everything the app can show of a vault: the feed with any errors, what the search passphrase reveals, and
    /// the tags.
    private struct Everything: Equatable {
        var feed: VaultRetrievalResult<VaultItem>
        var hidden: [VaultItem]
        var tags: [VaultItemTag]
    }

    private func readEverything(from store: any VaultStoreReader & VaultTagStoreReader) async throws -> Everything {
        let hidden = try await store.retrieve(
            query: .init(filterText: "find me"),
            searchPassphraseMatcher: searchPassphraseDigester,
        )
        return try await Everything(
            feed: store.retrieve(query: .init()),
            hidden: hidden.items,
            tags: store.retrieveTags(),
        )
    }
}

// MARK: - Fixtures

extension VaultEncryptionConverterSchemaTests {
    private static let tagID = UUID()
    private static let armedID = UUID()
    private static let hiddenID = UUID()
    private static let hotpID = UUID()
    private static let sealedID = UUID()
    private static let brokenID = UUID()

    /// An item of the fixture, in the raw values every schema stores.
    private struct FixtureItem {
        enum Kind {
            case note
            /// HOTP, counter 42.
            case hotp
            case encrypted
            /// An OTP code with an algorithm that doesn't exist, so it doesn't decode.
            case brokenOTP
        }

        var id: UUID
        var title: String
        var kind: Kind
        var killphrase: String?
        var searchPassphrase: String?
        var lockState: String?
        var color: PersistedColor?

        var visibility: String {
            searchPassphrase == nil ? VaultEncodingConstants.Visibility.always : VaultEncodingConstants.Visibility
                .onlySearch
        }

        var searchableLevel: String {
            searchPassphrase == nil ? VaultEncodingConstants.SearchableLevel.full : VaultEncodingConstants
                .SearchableLevel.onlyPassphrase
        }

        var isTagged: Bool {
            killphrase != nil
        }
    }

    private static let items = [
        FixtureItem(id: armedID, title: "armed", kind: .note, killphrase: "kill me"),
        FixtureItem(id: hiddenID, title: "hidden", kind: .note, searchPassphrase: "find me"),
        FixtureItem(
            id: hotpID,
            title: "hotp",
            kind: .hotp,
            lockState: VaultEncodingConstants.LockState.lockedWithNativeSecurity,
            color: PersistedColor(red: 0.25, green: 0.5, blue: 0.75),
        ),
        FixtureItem(id: sealedID, title: "sealed", kind: .encrypted),
        FixtureItem(id: brokenID, title: "broken", kind: .brokenOTP),
    ]

    /// The OTP details' fields: account, issuer, algorithm, type, counter, digits, period, secret, secret format.
    private static func otpFields(
        _ kind: FixtureItem.Kind,
    ) -> (String, String, String, String, Int64?, Int32, Int64?, Data, String) {
        switch kind {
        case .hotp:
            (
                "me",
                "Bank",
                VaultEncodingConstants.OTPAuthAlgorithm.sha1,
                VaultEncodingConstants.OTPAuthType.hotp,
                42,
                6,
                nil,
                Data([1, 2, 3, 4, 5]),
                VaultEncodingConstants.OTPAuthSecret.Format.base32,
            )
        default:
            (
                "me",
                "Bank",
                "INVALID",
                VaultEncodingConstants.OTPAuthType.totp,
                nil,
                6,
                30,
                Data([1, 2, 3]),
                VaultEncodingConstants.OTPAuthSecret.Format.base32,
            )
        }
    }

    /// The encrypted item's fields: version, title, data, authentication, IV, salt, signature.
    private static let encryptedFields = (
        "1.0.0", "Sealed", Data([1, 2]), Data([3, 4]), Data([5, 6]), Data([7, 8]),
        VaultKeyDeriver.Signature.testing.rawValue,
    )

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
        for fixture in Self.items {
            let otp = Self.otpFields(fixture.kind)
            let sealed = Self.encryptedFields
            context.insert(V1.PersistedVaultItem(
                id: fixture.id,
                relativeOrder: 0,
                createdDate: Date(),
                updatedDate: Date(),
                userDescription: fixture.title,
                visibility: fixture.visibility,
                searchableLevel: fixture.searchableLevel,
                searchPassphrase: fixture.searchPassphrase,
                killphrase: fixture.killphrase,
                lockState: fixture.lockState,
                color: fixture.color,
                showInQuickType: true,
                previewMode: NotePreviewMode.titleAndFirstLine.rawValue,
                tags: fixture.isTagged ? [tag] : [],
                noteDetails: fixture.kind == .note
                    ? V1.PersistedNoteDetails(title: fixture.title, contents: "contents", format: "PLAIN") : nil,
                otpDetails: fixture.kind == .hotp || fixture.kind == .brokenOTP
                    ? V1.PersistedOTPDetails(
                        accountName: otp.0, issuer: otp.1, algorithm: otp.2, authType: otp.3, counter: otp.4,
                        digits: otp.5, period: otp.6, secretData: otp.7, secretFormat: otp.8,
                    ) : nil,
                encryptedItemDetails: fixture.kind == .encrypted
                    ? V1.PersistedEncryptedItemDetails(
                        version: sealed.0, title: sealed.1, data: sealed.2, authentication: sealed.3,
                        encryptionIV: sealed.4, keygenSalt: sealed.5, keygenSignature: sealed.6,
                    ) : nil,
            ))
        }
        try context.save()
    }

    private func seedV2(at url: URL) throws {
        typealias V2 = PersistedSchemaV2
        let context = try Self.context(for: V2.self, at: url)
        let tag = V2.PersistedVaultTag(id: Self.tagID, title: "Work", color: nil, iconName: nil, items: [])
        context.insert(tag)
        for fixture in Self.items {
            let otp = Self.otpFields(fixture.kind)
            let sealed = Self.encryptedFields
            let killphrase = fixture.killphrase.map { killphraseDigester.makeDigest(phrase: $0) }
            context.insert(V2.PersistedVaultItem(
                id: fixture.id,
                relativeOrder: 0,
                createdDate: Date(),
                updatedDate: Date(),
                userDescription: fixture.title,
                visibility: fixture.visibility,
                searchableLevel: fixture.searchableLevel,
                searchPassphrase: fixture.searchPassphrase,
                killphraseSalt: killphrase?.salt,
                killphraseDigest: killphrase?.digest,
                lockState: fixture.lockState,
                color: fixture.color,
                showInQuickType: true,
                previewMode: NotePreviewMode.titleAndFirstLine.rawValue,
                tags: fixture.isTagged ? [tag] : [],
                noteDetails: fixture.kind == .note
                    ? V2.PersistedNoteDetails(title: fixture.title, contents: "contents", format: "PLAIN") : nil,
                otpDetails: fixture.kind == .hotp || fixture.kind == .brokenOTP
                    ? V2.PersistedOTPDetails(
                        accountName: otp.0, issuer: otp.1, algorithm: otp.2, authType: otp.3, counter: otp.4,
                        digits: otp.5, period: otp.6, secretData: otp.7, secretFormat: otp.8,
                    ) : nil,
                encryptedItemDetails: fixture.kind == .encrypted
                    ? V2.PersistedEncryptedItemDetails(
                        version: sealed.0, title: sealed.1, data: sealed.2, authentication: sealed.3,
                        encryptionIV: sealed.4, keygenSalt: sealed.5, keygenSignature: sealed.6,
                    ) : nil,
            ))
        }
        try context.save()
    }

    private func seedV3(at url: URL) throws {
        typealias V3 = PersistedSchemaV3
        let context = try Self.context(for: V3.self, at: url)
        let tag = V3.PersistedVaultTag(id: Self.tagID, title: "Work", color: nil, iconName: nil, items: [])
        context.insert(tag)
        for fixture in Self.items {
            let otp = Self.otpFields(fixture.kind)
            let sealed = Self.encryptedFields
            let killphrase = fixture.killphrase.map { killphraseDigester.makeDigest(phrase: $0) }
            let passphrase = fixture.searchPassphrase.map { searchPassphraseDigester.makeDigest(phrase: $0) }
            context.insert(V3.PersistedVaultItem(
                id: fixture.id,
                relativeOrder: 0,
                createdDate: Date(),
                updatedDate: Date(),
                userDescription: fixture.title,
                visibility: fixture.visibility,
                searchableLevel: fixture.searchableLevel,
                searchPassphraseSalt: passphrase?.salt,
                searchPassphraseDigest: passphrase?.digest,
                killphraseSalt: killphrase?.salt,
                killphraseDigest: killphrase?.digest,
                lockState: fixture.lockState,
                color: fixture.color,
                showInQuickType: true,
                previewMode: NotePreviewMode.titleAndFirstLine.rawValue,
                tags: fixture.isTagged ? [tag] : [],
                noteDetails: fixture.kind == .note
                    ? V3.PersistedNoteDetails(title: fixture.title, contents: "contents", format: "PLAIN") : nil,
                otpDetails: fixture.kind == .hotp || fixture.kind == .brokenOTP
                    ? V3.PersistedOTPDetails(
                        accountName: otp.0, issuer: otp.1, algorithm: otp.2, authType: otp.3, counter: otp.4,
                        digits: otp.5, period: otp.6, secretData: otp.7, secretFormat: otp.8,
                    ) : nil,
                encryptedItemDetails: fixture.kind == .encrypted
                    ? V3.PersistedEncryptedItemDetails(
                        version: sealed.0, title: sealed.1, data: sealed.2, authentication: sealed.3,
                        encryptionIV: sealed.4, keygenSalt: sealed.5, keygenSignature: sealed.6,
                    ) : nil,
            ))
        }
        try context.save()
    }

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
