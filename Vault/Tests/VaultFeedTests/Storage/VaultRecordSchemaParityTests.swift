import Foundation
import SwiftData
import Testing
@testable import VaultFeed

/// The records must carry every field of the latest persisted schema.
///
/// Records are how items move between stores, so a field the schema has and a record doesn't would be silently
/// dropped. When the schema changes, these tests fail until the record, and its copies to and from the models,
/// follow.
struct VaultRecordSchemaParityTests {
    @Test
    func everyEntityOfTheLatestSchemaHasARecord() {
        let entityNames = Set(Self.latestSchema.entities.map(\.name))

        #expect(entityNames == Set(Self.mirrorings.map(\.entityName)))
    }

    @Test(arguments: mirrorings)
    func recordCarriesEveryPersistedField(of mirroring: Mirroring) throws {
        let entity = try #require(Self.latestSchema.entities.first { $0.name == mirroring.entityName })
        let persistedFields = entity.attributes.map(\.name) + entity.relationships.map(\.name)

        let expectedRecordFields = Set(persistedFields
            .filter { mirroring.notMirrored[$0] == nil }
            .map { mirroring.renamed[$0] ?? $0 })

        let missing = expectedRecordFields.subtracting(mirroring.recordFields).sorted()
        let unexpected = mirroring.recordFields.subtracting(expectedRecordFields).sorted()
        #expect(missing.isEmpty, "Persisted but missing from the record: \(missing)")
        #expect(unexpected.isEmpty, "In the record but not persisted: \(unexpected)")
    }
}

// MARK: - Mirrorings

extension VaultRecordSchemaParityTests {
    /// How one entity of the schema maps onto the record type that mirrors it.
    struct Mirroring: CustomTestStringConvertible, Sendable {
        var entityName: String
        /// The stored properties of the record type.
        var recordFields: Set<String>
        /// Schema properties that the record names differently.
        var renamed: [String: String] = [:]
        /// Schema properties that deliberately have no record field, with the reason.
        var notMirrored: [String: String] = [:]

        var testDescription: String {
            entityName
        }
    }

    private static var latestSchema: Schema {
        Schema(versionedSchema: PersistedSchemaLatestVersion.self)
    }

    static let mirrorings: [Mirroring] = [
        Mirroring(
            entityName: "PersistedVaultItem",
            recordFields: fieldNames(of: anyItemRecord()),
            renamed: ["tags": "tagIDs"],
        ),
        Mirroring(
            entityName: "PersistedOTPDetails",
            recordFields: fieldNames(of: anyOTPDetails()),
            notMirrored: ["vaultItem": "Inverse of the item's `otpDetails`, which the item record nests"],
        ),
        Mirroring(
            entityName: "PersistedNoteDetails",
            recordFields: fieldNames(of: anyNoteDetails()),
            notMirrored: ["vaultItem": "Inverse of the item's `noteDetails`, which the item record nests"],
        ),
        Mirroring(
            entityName: "PersistedEncryptedItemDetails",
            recordFields: fieldNames(of: anyEncryptedItemDetails()),
            notMirrored: ["vaultItem": "Inverse of the item's `encryptedItemDetails`, which the item record nests"],
        ),
        Mirroring(
            entityName: "PersistedVaultTag",
            recordFields: fieldNames(of: VaultTagRecord(id: UUID(), title: "", color: nil, iconName: nil)),
            notMirrored: ["items": "Inverse of the item's `tags`, which item records carry as `tagIDs`"],
        ),
    ]

    private static func fieldNames(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    private static func anyItemRecord() -> VaultItemRecord {
        VaultItemRecord(
            id: UUID(),
            relativeOrder: 0,
            createdDate: Date(),
            updatedDate: Date(),
            userDescription: "",
            visibility: "",
            searchableLevel: "",
            searchPassphraseSalt: nil,
            searchPassphraseDigest: nil,
            killphraseSalt: nil,
            killphraseDigest: nil,
            lockState: nil,
            color: nil,
            showInQuickType: true,
            previewMode: "",
            tagIDs: [],
            noteDetails: nil,
            otpDetails: nil,
            encryptedItemDetails: nil,
        )
    }

    private static func anyOTPDetails() -> VaultItemRecord.OTPDetails {
        VaultItemRecord.OTPDetails(
            accountName: "",
            issuer: "",
            algorithm: "",
            authType: "",
            counter: nil,
            digits: 0,
            period: nil,
            secretData: Data(),
            secretFormat: "",
        )
    }

    private static func anyNoteDetails() -> VaultItemRecord.NoteDetails {
        VaultItemRecord.NoteDetails(title: "", contents: "", format: "")
    }

    private static func anyEncryptedItemDetails() -> VaultItemRecord.EncryptedItemDetails {
        VaultItemRecord.EncryptedItemDetails(
            version: "",
            title: "",
            data: Data(),
            authentication: Data(),
            encryptionIV: Data(),
            keygenSalt: Data(),
            keygenSignature: "",
        )
    }
}
