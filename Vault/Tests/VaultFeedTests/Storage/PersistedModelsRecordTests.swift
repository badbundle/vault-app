import Foundation
import FoundationExtensions
import SwiftData
import TestHelpers
import Testing
@testable import VaultFeed

/// Copying records into the SwiftData models and back must lose or change nothing, including values that don't
/// decode.
///
/// Each round trip saves through one context and reads back through a fresh one, so it checks what the store
/// actually persisted.
struct PersistedModelsRecordTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: PersistedVaultItem.self, PersistedVaultTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true),
        )
    }
}

// MARK: - Items

extension PersistedModelsRecordTests {
    @Test(arguments: [DetailKind.otp, .note, .encrypted])
    func item_everyFieldSurvivesTheRoundTrip(detail: DetailKind) throws {
        let tagIDs: Set<UUID> = [UUID(), UUID()]
        let record = makeFullRecord(tagIDs: tagIDs, detail: detail)

        try saveItem(record, withTags: tagIDs)

        #expect(try fetchItemRecord(id: record.id) == record)
    }

    @Test
    func item_emptyOptionalsSurviveTheRoundTrip() throws {
        var record = makeFullRecord(tagIDs: [], detail: .otp)
        record.searchPassphraseSalt = nil
        record.searchPassphraseDigest = nil
        record.killphraseSalt = nil
        record.killphraseDigest = nil
        record.lockState = nil
        record.color = nil
        record.otpDetails?.counter = nil
        record.otpDetails?.period = nil

        try saveItem(record, withTags: [])

        #expect(try fetchItemRecord(id: record.id) == record)
    }

    @Test
    func item_recordThatWouldNotDecodeSurvivesTheRoundTrip() throws {
        var record = makeFullRecord(tagIDs: [], detail: .otp)
        record.visibility = "NOT_A_VISIBILITY"
        record.otpDetails?.algorithm = "NOT_AN_ALGORITHM"
        #expect(throws: (any Error).self) {
            try PersistedVaultItemDecoder().decode(record: record)
        }

        try saveItem(record, withTags: [])

        #expect(try fetchItemRecord(id: record.id) == record)
    }

    @Test
    func item_noDetailSurvivesTheRoundTrip() throws {
        var record = makeFullRecord(tagIDs: [], detail: .otp)
        record.otpDetails = nil

        try saveItem(record, withTags: [])

        #expect(try fetchItemRecord(id: record.id) == record)
    }

    @Test
    func item_moreThanOneDetailSurvivesTheRoundTrip() throws {
        var record = makeFullRecord(tagIDs: [], detail: .otp)
        record.noteDetails = makeFullRecord(tagIDs: [], detail: .note).noteDetails
        record.encryptedItemDetails = makeFullRecord(tagIDs: [], detail: .encrypted).encryptedItemDetails

        try saveItem(record, withTags: [])

        #expect(try fetchItemRecord(id: record.id) == record)
    }

    @Test
    func item_tagIDsComeFromTheLinkedTags() throws {
        let context = ModelContext(container)
        let tags = [UUID(), UUID(), UUID()].map { id in
            PersistedVaultTag(record: VaultTagRecord(id: id, title: "Tag", color: nil, iconName: nil))
        }
        for tag in tags {
            context.insert(tag)
        }
        let record = makeFullRecord(tagIDs: [], detail: .otp)

        let model = PersistedVaultItem(record: record, tags: Array(tags.prefix(2)))
        context.insert(model)

        #expect(model.makeRecord().tagIDs == Set(tags.prefix(2).map(\.id)))
    }
}

// MARK: - Applying to items

extension PersistedModelsRecordTests {
    @Test(arguments: [DetailKind.otp, .note, .encrypted], [DetailKind.otp, .note, .encrypted])
    func item_applyReplacesEveryFieldTagsAndDetails(from before: DetailKind, to after: DetailKind) throws {
        let tagA = UUID()
        let tagB = UUID()
        let original = makeFullRecord(tagIDs: [tagA, tagB], detail: before)
        try saveItem(original, withTags: [tagA, tagB])
        var updated = makeFullRecord(tagIDs: [tagB], detail: after)
        updated.id = original.id

        let context = ModelContext(container)
        let model = try #require(try fetchItem(id: original.id, in: context))
        let tagModel = try #require(try fetchTag(id: tagB, in: context))
        model.apply(updated, tags: [tagModel], in: context)
        try context.save()

        #expect(try fetchItemRecord(id: original.id) == updated)
        #expect(try detailRowCounts() == DetailRowCounts(kind: after))
    }

    @Test
    func item_applyKeepsTheDetailRowForTheSameKind() throws {
        let original = makeFullRecord(tagIDs: [], detail: .note)
        try saveItem(original, withTags: [])
        var updated = original
        updated.noteDetails?.title = "A new title"
        updated.noteDetails?.contents = "New contents"

        let context = ModelContext(container)
        let model = try #require(try fetchItem(id: original.id, in: context))
        let detail = try #require(model.noteDetails)
        model.apply(updated, tags: [], in: context)
        try context.save()

        #expect(model.noteDetails === detail)
        #expect(try fetchItemRecord(id: original.id) == updated)
        #expect(try detailRowCounts() == DetailRowCounts(notes: 1))
    }
}

// MARK: - Tags

extension PersistedModelsRecordTests {
    @Test
    func tag_everyFieldSurvivesTheRoundTrip() throws {
        let record = VaultTagRecord(
            id: UUID(),
            title: "Tag title",
            color: PersistedColor(red: 0.1, green: 0.2, blue: 0.3),
            iconName: "star.fill",
        )

        try saveTag(record)

        #expect(try fetchTagRecord(id: record.id) == record)
    }

    @Test
    func tag_emptyOptionalsSurviveTheRoundTrip() throws {
        let record = VaultTagRecord(id: UUID(), title: "Tag title", color: nil, iconName: nil)

        try saveTag(record)

        #expect(try fetchTagRecord(id: record.id) == record)
    }

    @Test
    func tag_applyUpdatesFieldsInPlaceAndKeepsItsItems() throws {
        let tagID = UUID()
        let original = VaultTagRecord(id: tagID, title: "Before", color: nil, iconName: nil)
        try saveTag(original)
        let item = makeFullRecord(tagIDs: [tagID], detail: .note)
        try saveItem(item, withTags: [tagID])

        let context = ModelContext(container)
        let tag = try #require(try fetchTag(id: tagID, in: context))
        let updated = VaultTagRecord(
            id: tagID,
            title: "After",
            color: PersistedColor(red: 0.4, green: 0.5, blue: 0.6),
            iconName: "bolt.fill",
        )
        tag.apply(updated)
        try context.save()

        #expect(try fetchTagRecord(id: tagID) == updated)
        #expect(try fetchItemRecord(id: item.id).tagIDs == [tagID])
    }
}

// MARK: - Helpers

extension PersistedModelsRecordTests {
    enum DetailKind: CaseIterable, Sendable {
        case otp, note, encrypted
    }

    /// A record with every field set to something other than its default.
    private func makeFullRecord(tagIDs: Set<UUID>, detail: DetailKind) -> VaultItemRecord {
        VaultItemRecord(
            id: UUID(),
            relativeOrder: 42,
            createdDate: Date(timeIntervalSince1970: 1_000_000),
            updatedDate: Date(timeIntervalSince1970: 2_000_000),
            userDescription: "A description",
            visibility: VaultEncodingConstants.Visibility.onlySearch,
            searchableLevel: VaultEncodingConstants.SearchableLevel.onlyPassphrase,
            searchPassphraseSalt: Data.random(count: 16),
            searchPassphraseDigest: Data.random(count: 32),
            killphraseSalt: Data.random(count: 16),
            killphraseDigest: Data.random(count: 32),
            lockState: VaultEncodingConstants.LockState.lockedWithNativeSecurity,
            color: PersistedColor(red: 0.25, green: 0.5, blue: 0.75),
            showInQuickType: false,
            previewMode: NotePreviewMode.hidden.rawValue,
            tagIDs: tagIDs,
            noteDetails: detail == .note ? VaultItemRecord.NoteDetails(
                title: "Note title",
                contents: "Note contents\nwith more lines",
                format: VaultEncodingConstants.TextFormat.markdown,
            ) : nil,
            otpDetails: detail == .otp ? VaultItemRecord.OTPDetails(
                accountName: "account@example.com",
                issuer: "Issuer",
                algorithm: VaultEncodingConstants.OTPAuthAlgorithm.sha512,
                authType: VaultEncodingConstants.OTPAuthType.hotp,
                counter: 12,
                digits: 8,
                period: 45,
                secretData: Data.random(count: 20),
                secretFormat: VaultEncodingConstants.OTPAuthSecret.Format.base32,
            ) : nil,
            encryptedItemDetails: detail == .encrypted ? VaultItemRecord.EncryptedItemDetails(
                version: "1.2.3",
                title: "Encrypted title",
                data: Data.random(count: 64),
                authentication: Data.random(count: 16),
                encryptionIV: Data.random(count: 32),
                keygenSalt: Data.random(count: 48),
                keygenSignature: "vault.keygen.item.secure.v1",
            ) : nil,
        )
    }

    /// Saves the item, creating the tags it's linked to first.
    private func saveItem(_ record: VaultItemRecord, withTags tagIDs: Set<UUID>) throws {
        let context = ModelContext(container)
        var tags = [PersistedVaultTag]()
        for id in tagIDs {
            if let existing = try fetchTag(id: id, in: context) {
                tags.append(existing)
            } else {
                let tag = PersistedVaultTag(record: VaultTagRecord(id: id, title: "Tag", color: nil, iconName: nil))
                context.insert(tag)
                tags.append(tag)
            }
        }
        context.insert(PersistedVaultItem(record: record, tags: tags))
        try context.save()
    }

    private func saveTag(_ record: VaultTagRecord) throws {
        let context = ModelContext(container)
        context.insert(PersistedVaultTag(record: record))
        try context.save()
    }

    private func fetchItemRecord(id: UUID) throws -> VaultItemRecord {
        let context = ModelContext(container)
        return try #require(try fetchItem(id: id, in: context)).makeRecord()
    }

    private func fetchItem(id: UUID, in context: ModelContext) throws -> PersistedVaultItem? {
        let descriptor = FetchDescriptor<PersistedVaultItem>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    /// How many rows of each detail entity are stored, across every item.
    private func detailRowCounts() throws -> DetailRowCounts {
        let context = ModelContext(container)
        return try DetailRowCounts(
            otp: context.fetchCount(FetchDescriptor<PersistedOTPDetails>()),
            notes: context.fetchCount(FetchDescriptor<PersistedNoteDetails>()),
            encrypted: context.fetchCount(FetchDescriptor<PersistedEncryptedItemDetails>()),
        )
    }

    private struct DetailRowCounts: Equatable {
        var otp = 0
        var notes = 0
        var encrypted = 0

        init(otp: Int = 0, notes: Int = 0, encrypted: Int = 0) {
            self.otp = otp
            self.notes = notes
            self.encrypted = encrypted
        }

        /// One row of the given kind, and none of the others.
        init(kind: DetailKind) {
            switch kind {
            case .otp: self.init(otp: 1)
            case .note: self.init(notes: 1)
            case .encrypted: self.init(encrypted: 1)
            }
        }
    }

    private func fetchTagRecord(id: UUID) throws -> VaultTagRecord {
        let context = ModelContext(container)
        return try #require(try fetchTag(id: id, in: context)).makeRecord()
    }

    private func fetchTag(id: UUID, in context: ModelContext) throws -> PersistedVaultTag? {
        let descriptor = FetchDescriptor<PersistedVaultTag>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }
}
