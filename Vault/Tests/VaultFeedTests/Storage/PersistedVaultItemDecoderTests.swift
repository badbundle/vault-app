import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

struct PersistedVaultItemDecoderTests {}

// MARK: - Generic

extension PersistedVaultItemDecoderTests {
    @Test
    func decodeItem_missingItemDetail() throws {
        let sut = makeSUT()

        let persistedItem = makeRecord(
            noteDetails: nil,
            otpDetails: nil,
        )

        #expect(throws: (any Error).self) {
            try sut.decode(record: persistedItem)
        }
    }

    @Test
    func decodeItem_moreThanOneDetailPrefersOTPThenNote() throws {
        let sut = makeSUT()
        let note = makeNoteDetails(title: "Note")
        let encrypted = VaultItemRecord.EncryptedItemDetails(
            version: "1.0.0",
            title: "Encrypted",
            data: Data(),
            authentication: Data(),
            encryptionIV: Data(),
            keygenSalt: Data(),
            keygenSignature: "",
        )

        let all = try sut.decode(record: makeRecord(noteDetails: note, encryptedItemDetails: encrypted))
        let noteAndEncrypted = try sut.decode(record: makeRecord(
            noteDetails: note,
            otpDetails: nil,
            encryptedItemDetails: encrypted,
        ))

        #expect(all.item.otpCode != nil)
        #expect(noteAndEncrypted.item.secureNote?.title == "Note")
    }
}

// MARK: - Metadata

extension PersistedVaultItemDecoderTests {
    @Test
    func decodeMetadata_id() throws {
        let id = UUID()
        let item = makeRecord(id: id)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.id.rawValue == id)
    }

    @Test
    func decodeMetadata_createdDate() throws {
        let date = Date()
        let item = makeRecord(createdDate: date)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.metadata.created == date)
    }

    @Test
    func decodeMetadata_updatedDate() throws {
        let date = Date()
        let item = makeRecord(updatedDate: date)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.metadata.updated == date)
    }

    @Test
    func decodeMetadata_userDescription() throws {
        let description = "my description \(UUID().uuidString)"
        let item = makeRecord(userDescription: description)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.metadata.userDescription == description)
    }

    @Test
    func decodeMetadata_colorIsNil() throws {
        let item = makeRecord(color: nil)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.metadata.color == nil)
    }

    @Test
    func decodeMetadata_decodesColorValues() throws {
        let item = makeRecord(color: .init(red: 0.7, green: 0.6, blue: 0.5))
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        let expectedColor = VaultItemColor(red: 0.7, green: 0.6, blue: 0.5)
        #expect(decoded.metadata.color == expectedColor)
    }

    @Test
    func decodeMetadata_decodesQuickTypeAndPreviewMode() throws {
        let item = makeRecord(
            showInQuickType: false,
            previewMode: NotePreviewMode.hidden.rawValue,
        )
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.metadata.showInQuickType == false)
        #expect(decoded.metadata.previewMode == .hidden)
    }

    @Test
    func decodeMetadata_invalidPreviewModeDefaultsToTitleAndFirstLine() throws {
        let item = makeRecord(previewMode: "INVALID")
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.metadata.previewMode == .titleAndFirstLine)
    }

    @Test(arguments: [
        (VaultItemVisibility.always, "ALWAYS"),
        (VaultItemVisibility.onlySearch, "ONLY_SEARCH"),
    ])
    func decodeMetadata_decodesVisibilityLevels(expected: VaultItemVisibility, key: String) throws {
        let item = makeRecord(visibility: key)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.metadata.visibility == expected)
    }

    @Test
    func decodeMetadata_throwsForInvalidVisibilityLevel() throws {
        let item = makeRecord(visibility: "INVALID")
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(record: item)
        }
    }

    @Test(arguments: [
        (VaultItemSearchableLevel.full, "FULL"),
        (VaultItemSearchableLevel.none, "NONE"),
        (VaultItemSearchableLevel.onlyTitle, "ONLY_TITLE"),
        (VaultItemSearchableLevel.onlyPassphrase, "ONLY_PASSPHRASE"),
    ])
    func decodeMetadata_decodesSearchableLevels(expected: VaultItemSearchableLevel, key: String) throws {
        let item = makeRecord(searchableLevel: key)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)

        #expect(decoded.metadata.searchableLevel == expected)
    }

    @Test
    func decodeMetadata_throwsForInvalidSearchableLevel() throws {
        let item = makeRecord(searchableLevel: "INVALID")
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(record: item)
        }
    }

    @Test
    func decodeMetadata_decodesSearchPassphraseDigest() throws {
        let salt = Data(repeating: 0x11, count: 16)
        let digest = Data(repeating: 0x22, count: 32)
        let item = makeRecord(searchPassphraseSalt: salt, searchPassphraseDigest: digest)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.metadata.searchPassphrase == SearchPassphraseDigest(salt: salt, digest: digest))
    }

    @Test
    func decodeMetadata_decodesKillphraseDigest() throws {
        let salt = Data(repeating: 0xAB, count: 16)
        let digest = Data(repeating: 0xCD, count: 32)
        let item = makeRecord(killphraseSalt: salt, killphraseDigest: digest)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.metadata.killphrase == KillphraseDigest(salt: salt, digest: digest))
    }

    @Test
    func decodeMetadata_decodesKillphraseAsNilWhenOnlyOneSideStored() throws {
        let item = makeRecord(
            killphraseSalt: Data(repeating: 0xAB, count: 16),
            killphraseDigest: nil,
        )
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.metadata.killphrase == nil)
    }

    @Test
    func decodeMetadata_decodesEmptyItemTags() throws {
        let item = makeRecord(tagIDs: [])
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.metadata.tags == [])
    }

    @Test
    func decodeMetadata_decodesItemTags() throws {
        let id1 = UUID()
        let id2 = UUID()
        let item = makeRecord(tagIDs: [id1, id2])
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.metadata.tags == [.init(id: id1), .init(id: id2)])
    }

    @Test
    func decodeLockState_nilIsNotLocked() throws {
        let item = makeRecord(lockState: nil)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.metadata.lockState == .notLocked)
    }

    @Test
    func decodeLockState_notLocked() throws {
        let item = makeRecord(lockState: "NOT_LOCKED")
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.metadata.lockState == .notLocked)
    }

    @Test
    func decodeLockState_lockedNative() throws {
        let item = makeRecord(lockState: "LOCKED_NATIVE")
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.metadata.lockState == .lockedWithNativeSecurity)
    }

    @Test
    func decodeLockState_invalidValueThrows() throws {
        let item = makeRecord(lockState: "INVALID")
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(record: item)
        }
    }
}

// MARK: - OTP Code

extension PersistedVaultItemDecoderTests {
    @Test(arguments: [
        (OTPAuthDigits(value: 0), Int32(0)),
        (OTPAuthDigits(value: 6), Int32(6)),
        (OTPAuthDigits(value: 7), Int32(7)),
        (OTPAuthDigits(value: 8), Int32(8)),
        (OTPAuthDigits(value: 100), Int32(100)),
        (OTPAuthDigits(value: 1024), Int32(1024)),
    ])
    func decodeOTP_digits(expectedDigits: OTPAuthDigits, value: Int32) throws {
        let sut = makeSUT()
        let otpDetails = makeOTPDetails(digits: value)
        let item = makeRecord(otpDetails: otpDetails)

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.data.digits == expectedDigits)
    }

    @Test(arguments: [Int32(-33), Int32(333_333)])
    func decodeOTP_invalidDigits(value: Int32) throws {
        let sut = makeSUT()
        let otpDetails = makeOTPDetails(digits: value)
        let item = makeRecord(otpDetails: otpDetails)

        #expect(throws: (any Error).self) {
            try sut.decode(record: item)
        }
    }

    @Test
    func decodeOTP_accountName() throws {
        let accountName = UUID().uuidString
        let otpDetails = makeOTPDetails(accountName: accountName)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.data.accountName == accountName)
    }

    @Test
    func decodeOTP_issuer() throws {
        let issuerName = UUID().uuidString
        let otpDetails = makeOTPDetails(issuer: issuerName)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.data.issuer == issuerName)
    }

    @Test
    func decodeOTP_authTypeTOTPWithPeriod() throws {
        let otpDetails = makeOTPDetails(authType: "totp", period: 69)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.type == .totp(period: 69))
    }

    @Test
    func decodeOTP_authTypeTOTPWithoutPeriodThrows() throws {
        let otpDetails = makeOTPDetails(authType: "totp", period: nil)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(record: item)
        }
    }

    @Test
    func decodeOTP_authTypeHOTPWithCounter() throws {
        let otpDetails = makeOTPDetails(authType: "hotp", counter: 69)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.type == .hotp(counter: 69))
    }

    @Test
    func decodeOTP_authTypeHOTPWithoutCounterThrows() throws {
        let otpDetails = makeOTPDetails(authType: "hotp", counter: nil)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(record: item)
        }
    }

    @Test(arguments: [
        (OTPAuthAlgorithm.sha1, "SHA1"),
        (OTPAuthAlgorithm.sha256, "SHA256"),
        (OTPAuthAlgorithm.sha512, "SHA512"),
    ])
    func decodeOTP_algorithm(expected: OTPAuthAlgorithm, string: String) throws {
        let otpDetails = makeOTPDetails(algorithm: string)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.data.algorithm == expected)
    }

    @Test
    func decodeOTP_invalidAlgorithmThrows() throws {
        let otpDetails = makeOTPDetails(algorithm: "OTHER")
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(record: item)
        }
    }

    @Test(arguments: [(OTPAuthSecret.Format.base32, "BASE_32")])
    func decodeOTP_secretFormat(expected: OTPAuthSecret.Format, string: String) throws {
        let otpDetails = makeOTPDetails(secretFormat: string)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.data.secret.format == expected)
    }

    @Test
    func decodeOTP_secretFormatInvalidThrows() throws {
        let otpDetails = makeOTPDetails(secretFormat: "INVALID")
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(record: item)
        }
    }

    @Test
    func decodeOTP_emptySecret() throws {
        let otpDetails = makeOTPDetails(secretData: Data())
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.data.secret.data == Data())
    }

    @Test
    func decodeOTP_nonEmptySecret() throws {
        let data = Data([0xFF, 0xEE, 0x11, 0x12, 0x13, 0x56])
        let otpDetails = makeOTPDetails(secretData: data)
        let item = makeRecord(otpDetails: otpDetails)
        let sut = makeSUT()

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.otpCode?.data.secret.data == data)
    }
}

// MARK: - Secure Note

extension PersistedVaultItemDecoderTests {
    @Test
    func decodeNote_title() throws {
        let sut = makeSUT()

        let title = "this is my note title"
        let noteDetails = makeNoteDetails(title: title)
        let item = makeRecord(noteDetails: noteDetails, otpDetails: nil)

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.secureNote?.title == title)
    }

    @Test
    func decodeNote_contents() throws {
        let sut = makeSUT()

        let contents = "this is my note contents"
        let noteDetails = makeNoteDetails(contents: contents)
        let item = makeRecord(noteDetails: noteDetails, otpDetails: nil)

        let decoded = try sut.decode(record: item)
        #expect(decoded.item.secureNote?.contents == contents)
    }
}

// MARK: - EncryptedItem

extension PersistedVaultItemDecoderTests {
    @Test
    func decodeEncryptedItem_correctly() throws {
        let sut = makeSUT()

        let itemData = Data.random(count: 16)
        let itemAuth = Data.random(count: 16)
        let itemEncryptionIV = Data.random(count: 16)
        let itemKeygenSalt = Data.random(count: 16)
        let itemKeygenSignature = "my sig"
        let encryptedItem = VaultItemRecord.EncryptedItemDetails(
            version: "1.0.3",
            title: "cool title",
            data: itemData,
            authentication: itemAuth,
            encryptionIV: itemEncryptionIV,
            keygenSalt: itemKeygenSalt,
            keygenSignature: itemKeygenSignature,
        )
        let item = makeRecord(otpDetails: nil, encryptedItemDetails: encryptedItem)

        let decoded = try sut.decode(record: item)

        #expect(decoded.item.encryptedItem?.version == "1.0.3")
        #expect(decoded.item.encryptedItem?.title == "cool title")
        #expect(decoded.item.encryptedItem?.data == itemData)
        #expect(decoded.item.encryptedItem?.authentication == itemAuth)
        #expect(decoded.item.encryptedItem?.encryptionIV == itemEncryptionIV)
        #expect(decoded.item.encryptedItem?.keygenSalt == itemKeygenSalt)
        #expect(decoded.item.encryptedItem?.keygenSignature == itemKeygenSignature)
    }
}

// MARK: - Helpers

extension PersistedVaultItemDecoderTests {
    private func makeSUT() -> PersistedVaultItemDecoder {
        PersistedVaultItemDecoder()
    }

    private func makeRecord(
        id: UUID = UUID(),
        relativeOrder: UInt64 = .min,
        createdDate: Date = Date(),
        updatedDate: Date = Date(),
        userDescription: String = "",
        visibility: String = "ALWAYS",
        searchableLevel: String = "FULL",
        searchPassphraseSalt: Data? = nil,
        searchPassphraseDigest: Data? = nil,
        killphrase _: String? = nil,
        killphraseSalt: Data? = nil,
        killphraseDigest: Data? = nil,
        lockState: String? = nil,
        color: PersistedColor? = nil,
        showInQuickType: Bool = true,
        previewMode: String = NotePreviewMode.titleAndFirstLine.rawValue,
        tagIDs: Set<UUID> = [],
        noteDetails: VaultItemRecord.NoteDetails? = nil,
        otpDetails: VaultItemRecord.OTPDetails? = .init(
            accountName: "",
            issuer: "",
            algorithm: VaultEncodingConstants.OTPAuthAlgorithm.sha1,
            authType: VaultEncodingConstants.OTPAuthType.totp,
            counter: 0,
            digits: 1,
            period: 0,
            secretData: Data(),
            secretFormat: VaultEncodingConstants.OTPAuthSecret.Format.base32,
        ),
        encryptedItemDetails: VaultItemRecord.EncryptedItemDetails? = nil,
    ) -> VaultItemRecord {
        VaultItemRecord(
            id: id,
            relativeOrder: relativeOrder,
            createdDate: createdDate,
            updatedDate: updatedDate,
            userDescription: userDescription,
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphraseSalt: searchPassphraseSalt,
            searchPassphraseDigest: searchPassphraseDigest,
            killphraseSalt: killphraseSalt,
            killphraseDigest: killphraseDigest,
            lockState: lockState,
            color: color,
            showInQuickType: showInQuickType,
            previewMode: previewMode,
            tagIDs: tagIDs,
            noteDetails: noteDetails,
            otpDetails: otpDetails,
            encryptedItemDetails: encryptedItemDetails,
        )
    }

    private func makeOTPDetails(
        accountName: String = "",
        algorithm: String = VaultEncodingConstants.OTPAuthAlgorithm.sha1,
        authType: String = VaultEncodingConstants.OTPAuthType.totp,
        counter: Int64? = 0,
        digits: Int32 = 1,
        issuer: String = "",
        period: Int64? = 0,
        secretData: Data = Data(),
        secretFormat: String = VaultEncodingConstants.OTPAuthSecret.Format.base32,
    ) -> VaultItemRecord.OTPDetails {
        VaultItemRecord.OTPDetails(
            accountName: accountName,
            issuer: issuer,
            algorithm: algorithm,
            authType: authType,
            counter: counter,
            digits: digits,
            period: period,
            secretData: secretData,
            secretFormat: secretFormat,
        )
    }

    private func makeNoteDetails(
        title: String = "my title",
        contents: String = "",
        format: String = VaultEncodingConstants.TextFormat.plain,
    ) -> VaultItemRecord.NoteDetails {
        VaultItemRecord.NoteDetails(title: title, contents: contents, format: format)
    }
}
