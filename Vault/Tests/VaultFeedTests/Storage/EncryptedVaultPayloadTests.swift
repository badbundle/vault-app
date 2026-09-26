import Foundation
import Testing
@testable import VaultFeed

struct EncryptedVaultPayloadTests {
    @Test
    func encode_roundTripsEveryFieldOfEveryRecord() throws {
        let state = VaultRecordState(items: [Self.everyFieldItem(), Self.fewestFieldsItem()], tags: [Self.tag()])

        let payload = try EncryptedVaultPayload.encode(state)

        #expect(payload.version == 1)
        #expect(try EncryptedVaultPayload.decode(payload) == state)
    }

    /// The round trip only proves a field survives if the record sets it, so a new optional field has to be set here.
    @Test
    func everyFieldItem_setsEveryOptionalField() {
        let unset = Self.optionalFieldsLeftUnset(in: Self.everyFieldItem())
            + Self.optionalFieldsLeftUnset(in: Self.tag())

        #expect(unset.isEmpty, "Set these in the fixture: \(unset)")
    }

    @Test
    func encode_roundTripsDatesExactly() throws {
        let dates = [Date(), Date(timeIntervalSinceReferenceDate: 0.1), .distantPast, .distantFuture]
            + (0 ..< 500).map { _ in Date(timeIntervalSinceReferenceDate: .random(in: -2e9 ... 2e9)) }
        let items = dates.map { date in
            var item = Self.fewestFieldsItem()
            item.createdDate = date
            item.updatedDate = date.addingTimeInterval(0.000_1)
            return item
        }
        let state = VaultRecordState(items: items, tags: [])

        let decoded = try EncryptedVaultPayload.decode(EncryptedVaultPayload.encode(state))

        #expect(decoded.items.map(\.createdDate) == dates)
        #expect(decoded == state)
    }

    @Test
    func encode_roundTripsAnEmptyVault() throws {
        #expect(try EncryptedVaultPayload.decode(EncryptedVaultPayload.encode(.empty)) == .empty)
    }

    /// A vault saved by this version must keep reading in every later one, so the keys and the value encodings
    /// can't change.
    @Test
    func decode_readsVersion1AsItWasFirstWritten() throws {
        let json = """
        {"items":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","relativeOrder":7,"createdDate":700000000.25,\
        "updatedDate":700000001.5,"userDescription":"Bank","visibility":"ONLY_SEARCH","searchableLevel":"FULL",\
        "searchPassphraseSalt":"AQI=","searchPassphraseDigest":"AwQ=","killphraseSalt":"BQY=",\
        "killphraseDigest":"Bwg=","lockState":"LOCKED_NATIVE","color":{"red":0.25,"green":0.5,"blue":0.75},\
        "showInQuickType":false,"previewMode":"titleOnly","tagIDs":["0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"],\
        "noteDetails":{"title":"Note","contents":"Contents","format":"MARKDOWN"},\
        "otpDetails":{"accountName":"me@example.com","issuer":"Bank","algorithm":"SHA256","authType":"hotp",\
        "counter":9223372036854775807,"digits":8,"period":30,"secretData":"CQo=","secretFormat":"BASE_32"},\
        "encryptedItemDetails":{"version":"1.0.0","title":"Secret","data":"Cww=","authentication":"DQ4=",\
        "encryptionIV":"DxA=","keygenSalt":"ERI=","keygenSignature":"ITEM_SECURE_V1"}}],\
        "tags":[{"id":"0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0","title":"Work",\
        "color":{"red":1,"green":0,"blue":0.5},"iconName":"briefcase"}]}
        """

        let state = try EncryptedVaultPayload.decode(VaultSlotPayload(version: 1, data: Data(json.utf8)))

        #expect(state == VaultRecordState(items: [Self.everyFieldItem()], tags: [Self.tag()]))
    }

    @Test
    func decode_readsARecordWithoutItsOptionalFields() throws {
        let json = """
        {"items":[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","relativeOrder":0,"createdDate":0,\
        "updatedDate":0,"userDescription":"","visibility":"ALWAYS","searchableLevel":"NONE",\
        "showInQuickType":true,"previewMode":"titleAndFirstLine","tagIDs":[]}],\
        "tags":[{"id":"0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0","title":"Work"}]}
        """

        let state = try EncryptedVaultPayload.decode(VaultSlotPayload(version: 1, data: Data(json.utf8)))

        #expect(state.items == [Self.fewestFieldsItem()])
        #expect(state.tags.map(\.iconName) == [nil])
        #expect(state.tags.map(\.color) == [nil])
    }

    @Test(arguments: [UInt32(0), 2, .max])
    func decode_refusesAVersionItDoesNotKnow(version: UInt32) throws {
        let payload = try EncryptedVaultPayload.encode(VaultRecordState(items: [Self.everyFieldItem()], tags: []))

        #expect(throws: EncryptedVaultStoreError.unsupportedPayloadVersion(version)) {
            try EncryptedVaultPayload.decode(VaultSlotPayload(version: version, data: payload.data))
        }
    }

    @Test
    func decode_throwsForDataThatIsNotAPayload() {
        for data in [Data(), Data("{}".utf8), Data("[]".utf8), Data(#"{"items":[],"tags":[{}]}"#.utf8)] {
            #expect(throws: DecodingError.self) {
                try EncryptedVaultPayload.decode(VaultSlotPayload(version: 1, data: data))
            }
        }
    }
}

// MARK: - Fixtures

extension EncryptedVaultPayloadTests {
    /// A record with every field set, to values the golden JSON above spells out.
    private static func everyFieldItem() -> VaultItemRecord {
        VaultItemRecord(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            relativeOrder: 7,
            createdDate: Date(timeIntervalSinceReferenceDate: 700_000_000.25),
            updatedDate: Date(timeIntervalSinceReferenceDate: 700_000_001.5),
            userDescription: "Bank",
            visibility: VaultEncodingConstants.Visibility.onlySearch,
            searchableLevel: VaultEncodingConstants.SearchableLevel.full,
            searchPassphraseSalt: Data([1, 2]),
            searchPassphraseDigest: Data([3, 4]),
            killphraseSalt: Data([5, 6]),
            killphraseDigest: Data([7, 8]),
            lockState: VaultEncodingConstants.LockState.lockedWithNativeSecurity,
            color: PersistedColor(red: 0.25, green: 0.5, blue: 0.75),
            showInQuickType: false,
            previewMode: NotePreviewMode.titleOnly.rawValue,
            tagIDs: [UUID(uuidString: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")!],
            noteDetails: .init(title: "Note", contents: "Contents", format: VaultEncodingConstants.TextFormat.markdown),
            otpDetails: .init(
                accountName: "me@example.com",
                issuer: "Bank",
                algorithm: VaultEncodingConstants.OTPAuthAlgorithm.sha256,
                authType: VaultEncodingConstants.OTPAuthType.hotp,
                counter: .max,
                digits: 8,
                period: 30,
                secretData: Data([9, 10]),
                secretFormat: VaultEncodingConstants.OTPAuthSecret.Format.base32,
            ),
            encryptedItemDetails: .init(
                version: "1.0.0",
                title: "Secret",
                data: Data([11, 12]),
                authentication: Data([13, 14]),
                encryptionIV: Data([15, 16]),
                keygenSalt: Data([17, 18]),
                keygenSignature: "ITEM_SECURE_V1",
            ),
        )
    }

    /// A record with every optional field left out.
    private static func fewestFieldsItem() -> VaultItemRecord {
        VaultItemRecord(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            relativeOrder: 0,
            createdDate: Date(timeIntervalSinceReferenceDate: 0),
            updatedDate: Date(timeIntervalSinceReferenceDate: 0),
            userDescription: "",
            visibility: VaultEncodingConstants.Visibility.always,
            searchableLevel: VaultEncodingConstants.SearchableLevel.none,
            searchPassphraseSalt: nil,
            searchPassphraseDigest: nil,
            killphraseSalt: nil,
            killphraseDigest: nil,
            lockState: nil,
            color: nil,
            showInQuickType: true,
            previewMode: NotePreviewMode.titleAndFirstLine.rawValue,
            tagIDs: [],
            noteDetails: nil,
            otpDetails: nil,
            encryptedItemDetails: nil,
        )
    }

    private static func tag() -> VaultTagRecord {
        VaultTagRecord(
            id: UUID(uuidString: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")!,
            title: "Work",
            color: PersistedColor(red: 1, green: 0, blue: 0.5),
            iconName: "briefcase",
        )
    }

    /// The paths of optional fields that are `nil`, looking inside nested values.
    private static func optionalFieldsLeftUnset(in value: Any, path: String = "") -> [String] {
        Mirror(reflecting: value).children.flatMap { child -> [String] in
            let childPath = path + "." + (child.label ?? "?")
            let mirror = Mirror(reflecting: child.value)
            guard mirror.displayStyle == .optional else { return [] }
            guard let wrapped = mirror.children.first?.value else { return [childPath] }
            return optionalFieldsLeftUnset(in: wrapped, path: childPath)
        }
    }
}
