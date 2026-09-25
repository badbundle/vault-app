import Foundation
import FoundationExtensions
import SwiftData
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

struct PersistedVaultItemEncoderTests {
    private let context: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistedVaultItem.self, configurations: config)
        context = ModelContext(container)
    }
}

// MARK: - Metadata

extension PersistedVaultItemEncoderTests {
    @Test
    func encodeMetadata_usesSameDateForCreatedAndUpdated() throws {
        var currentEpochSeconds = 100.0
        let sut = makeSUT(currentDate: {
            // Ensures the time increments every time the date is fetched
            currentEpochSeconds += 1
            return Date(timeIntervalSince1970: currentEpochSeconds)
        })

        let newItem = try encode(sut: sut, item: uniqueVaultItem().makeWritable())
        #expect(newItem.createdDate == newItem.updatedDate)
    }

    @Test
    func encodeMetadata_existingItemRetainsUUID() throws {
        let sut = makeSUT()

        let existing = try encode(sut: sut, item: uniqueVaultItem().makeWritable())
        let existingID = existing.id

        let newCode = try encode(sut: sut, item: uniqueVaultItem().makeWritable(), existing: existing)
        #expect(newCode.id == existingID)
    }

    @Test
    func encodeMetadata_existingItemRetainsCreatedDate() throws {
        let sut1 = makeSUT(currentDate: { Date(timeIntervalSince1970: 100) })

        let existing = try encode(sut: sut1, item: uniqueVaultItem().makeWritable())
        let existingCreatedDate = existing.createdDate

        let sut2 = makeSUT(currentDate: { Date(timeIntervalSince1970: 200) })
        let newCode = try encode(sut: sut2, item: uniqueVaultItem().makeWritable(), existing: existing)
        #expect(newCode.createdDate == existingCreatedDate)
    }

    @Test
    func encodeMetadata_existingItemUpdatesUpdatedDate() throws {
        let sut1 = makeSUT(currentDate: { Date(timeIntervalSince1970: 100) })

        let existing = try encode(sut: sut1, item: uniqueVaultItem().makeWritable())

        let sut2 = makeSUT(currentDate: { Date(timeIntervalSince1970: 200) })
        let newCode = try encode(sut: sut2, item: uniqueVaultItem().makeWritable(), existing: existing)
        #expect(newCode.updatedDate == Date(timeIntervalSince1970: 200))
    }

    @Test
    func encodeMetadata_newItemGeneratesRandomUUID() throws {
        var seen = Set<UUID>()
        for _ in 0 ..< 100 {
            let sut = makeSUT()
            let code = makeWritable(code: makeCodeValue())

            let encoded = try encode(sut: sut, item: code)
            #expect(!seen.contains(encoded.id))
            seen.insert(encoded.id)
        }
    }

    @Test
    func encodeMetadata_newItemUserDescriptionEncodesString() throws {
        let sut = makeSUT()
        let desc = UUID().uuidString
        let code = makeWritable(userDescription: desc, code: uniqueCode())

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.userDescription == desc)
    }

    @Test
    func encodeMetadata_newItemIgnoresForNoColor() throws {
        let sut = makeSUT()
        let code = makeWritable(code: uniqueCode(), color: nil)

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.color == nil)
    }

    @Test
    func encodeMetadata_newItemWritesColorValues() throws {
        let sut = makeSUT()
        let color = VaultItemColor(red: 0.5, green: 0.6, blue: 0.7)
        let code = makeWritable(code: uniqueCode(), color: color)

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.color?.red == 0.5)
        #expect(encoded.color?.green == 0.6)
        #expect(encoded.color?.blue == 0.7)
    }

    @Test
    func encodeMetadata_existingItemOverridesColorValues() throws {
        let sut1 = makeSUT()

        var existingItem = uniqueVaultItem().makeWritable()
        existingItem.color = VaultItemColor(red: 0.1, green: 0.2, blue: 0.3)
        let existing = try encode(sut: sut1, item: existingItem)

        let color = VaultItemColor(red: 0.5, green: 0.6, blue: 0.7)
        let sut2 = makeSUT()
        let code = makeWritable(code: uniqueCode(), color: color)

        let newCode = try encode(sut: sut2, item: code, existing: existing)
        #expect(newCode.color?.red == 0.5)
        #expect(newCode.color?.green == 0.6)
        #expect(newCode.color?.blue == 0.7)
    }

    @Test
    func encodeMetadata_encodesQuickTypeAndPreviewMode() throws {
        let sut = makeSUT()
        let item = makeWritable(
            code: uniqueCode(),
            showInQuickType: false,
            previewMode: .hidden,
        )

        let encoded = try encode(sut: sut, item: item)

        #expect(encoded.showInQuickType == false)
        #expect(encoded.previewMode == NotePreviewMode.hidden.rawValue)
    }

    @Test(arguments: [
        (VaultItemVisibility.always, "ALWAYS"),
        (VaultItemVisibility.onlySearch, "ONLY_SEARCH"),
    ])
    func encodeMetadata_newItemEncodesVisibilityLevels(value: VaultItemVisibility, key: String) throws {
        let sut1 = makeSUT()
        var existingItem = uniqueVaultItem().makeWritable()
        existingItem.visibility = value
        let existing = try encode(sut: sut1, item: existingItem)

        #expect(existing.visibility == key)
    }

    @Test(arguments: [
        (VaultItemVisibility.always, "ALWAYS"),
        (VaultItemVisibility.onlySearch, "ONLY_SEARCH"),
    ])
    func encodeMetadata_existingItemEncodesVisibilityLevels(value: VaultItemVisibility, key: String) throws {
        let sut = makeSUT()
        var item1 = uniqueVaultItem().makeWritable()
        item1.visibility = .onlySearch
        let existing = try encode(sut: sut, item: item1)

        var item2 = uniqueVaultItem().makeWritable()
        item2.visibility = value
        let existing2 = try encode(sut: sut, item: item2, existing: existing)

        #expect(existing2.visibility == key)
    }

    @Test(arguments: [
        (VaultItemSearchableLevel.full, "FULL"),
        (VaultItemSearchableLevel.none, "NONE"),
        (VaultItemSearchableLevel.onlyTitle, "ONLY_TITLE"),
        (VaultItemSearchableLevel.onlyPassphrase, "ONLY_PASSPHRASE"),
    ])
    func encodeMetadata_newItemEncodesSearchableLevels(value: VaultItemSearchableLevel, key: String) throws {
        let sut1 = makeSUT()
        var existingItem = uniqueVaultItem().makeWritable()
        existingItem.searchableLevel = value
        let existing = try encode(sut: sut1, item: existingItem)

        #expect(existing.searchableLevel == key)
    }

    @Test(arguments: [
        (VaultItemSearchableLevel.full, "FULL"),
        (VaultItemSearchableLevel.none, "NONE"),
        (VaultItemSearchableLevel.onlyTitle, "ONLY_TITLE"),
        (VaultItemSearchableLevel.onlyPassphrase, "ONLY_PASSPHRASE"),
    ])
    func encodeMetadata_existingItemEncodesSearchableLevels(value: VaultItemSearchableLevel, key: String) throws {
        let sut = makeSUT()
        var item1 = uniqueVaultItem().makeWritable()
        item1.searchableLevel = .none
        let existing = try encode(sut: sut, item: item1)

        var item2 = uniqueVaultItem().makeWritable()
        item2.searchableLevel = value
        let existing2 = try encode(sut: sut, item: item2, existing: existing)

        #expect(existing2.searchableLevel == key)
    }

    @Test
    func encodeMetadata_newItemEncodesSearchPassphraseDigest() throws {
        let sut1 = makeSUT()
        let digest = SearchPassphraseDigest(
            salt: Data(repeating: 0x11, count: 16),
            digest: Data(repeating: 0x22, count: 32),
        )
        var existingItem = uniqueVaultItem().makeWritable()
        existingItem.searchPassphraseUpdate = .set(digest)
        let existing = try encode(sut: sut1, item: existingItem)

        #expect(existing.searchPassphraseSalt == digest.salt)
        #expect(existing.searchPassphraseDigest == digest.digest)
    }

    @Test
    func encodeMetadata_existingItemReplacesSearchPassphraseDigest() throws {
        let sut = makeSUT()
        let first = SearchPassphraseDigest(
            salt: Data(repeating: 0x01, count: 16),
            digest: Data(repeating: 0x02, count: 32),
        )
        let second = SearchPassphraseDigest(
            salt: Data(repeating: 0x03, count: 16),
            digest: Data(repeating: 0x04, count: 32),
        )
        var item1 = uniqueVaultItem().makeWritable()
        item1.searchPassphraseUpdate = .set(first)
        let existing = try encode(sut: sut, item: item1)

        var item2 = uniqueVaultItem().makeWritable()
        item2.searchPassphraseUpdate = .set(second)
        let existing2 = try encode(sut: sut, item: item2, existing: existing)

        #expect(existing2.searchPassphraseSalt == second.salt)
        #expect(existing2.searchPassphraseDigest == second.digest)
    }

    @Test
    func encodeMetadata_unchangedSearchPassphraseKeepsExisting() throws {
        let sut = makeSUT()
        let digest = SearchPassphraseDigest(
            salt: Data(repeating: 0x05, count: 16),
            digest: Data(repeating: 0x06, count: 32),
        )
        var item1 = uniqueVaultItem().makeWritable()
        item1.searchPassphraseUpdate = .set(digest)
        let existing = try encode(sut: sut, item: item1)

        var item2 = uniqueVaultItem().makeWritable()
        item2.searchPassphraseUpdate = .unchanged
        let existing2 = try encode(sut: sut, item: item2, existing: existing)

        #expect(existing2.searchPassphraseSalt == digest.salt)
        #expect(existing2.searchPassphraseDigest == digest.digest)
    }

    @Test
    func encodeMetadata_clearSearchPassphraseRemovesDigest() throws {
        let sut = makeSUT()
        let digest = SearchPassphraseDigest(
            salt: Data(repeating: 0x07, count: 16),
            digest: Data(repeating: 0x08, count: 32),
        )
        var item1 = uniqueVaultItem().makeWritable()
        item1.searchPassphraseUpdate = .set(digest)
        let existing = try encode(sut: sut, item: item1)

        var item2 = uniqueVaultItem().makeWritable()
        item2.searchPassphraseUpdate = .clear
        let existing2 = try encode(sut: sut, item: item2, existing: existing)

        #expect(existing2.searchPassphraseSalt == nil)
        #expect(existing2.searchPassphraseDigest == nil)
    }

    @Test
    func encodeMetadata_newItemEncodesKillphraseDigest() throws {
        let sut1 = makeSUT()
        let digest = KillphraseDigest(
            salt: Data(repeating: 0xAB, count: 16),
            digest: Data(repeating: 0xCD, count: 32),
        )
        var existingItem = uniqueVaultItem().makeWritable()
        existingItem.killphraseUpdate = .set(digest)
        let existing = try encode(sut: sut1, item: existingItem)

        #expect(existing.killphraseSalt == digest.salt)
        #expect(existing.killphraseDigest == digest.digest)
    }

    @Test
    func encodeMetadata_existingItemReplacesKillphraseDigest() throws {
        let sut = makeSUT()
        let d1 = KillphraseDigest(salt: Data(repeating: 0x01, count: 16), digest: Data(repeating: 0xA1, count: 32))
        let d2 = KillphraseDigest(salt: Data(repeating: 0x02, count: 16), digest: Data(repeating: 0xA2, count: 32))
        var item1 = uniqueVaultItem().makeWritable()
        item1.killphraseUpdate = .set(d1)
        let existing = try encode(sut: sut, item: item1)

        var item2 = uniqueVaultItem().makeWritable()
        item2.killphraseUpdate = .set(d2)
        let existing2 = try encode(sut: sut, item: item2, existing: existing)

        #expect(existing2.killphraseSalt == d2.salt)
        #expect(existing2.killphraseDigest == d2.digest)
    }

    @Test
    func encodeMetadata_unchangedKillphrasePreservesExistingDigest() throws {
        let sut = makeSUT()
        let d = KillphraseDigest(salt: Data(repeating: 0x03, count: 16), digest: Data(repeating: 0xA3, count: 32))
        var item1 = uniqueVaultItem().makeWritable()
        item1.killphraseUpdate = .set(d)
        let existing = try encode(sut: sut, item: item1)

        var item2 = uniqueVaultItem().makeWritable()
        item2.killphraseUpdate = .unchanged
        let existing2 = try encode(sut: sut, item: item2, existing: existing)

        #expect(existing2.killphraseSalt == d.salt)
        #expect(existing2.killphraseDigest == d.digest)
    }

    @Test
    func encodeMetadata_clearKillphraseRemovesDigest() throws {
        let sut = makeSUT()
        let d = KillphraseDigest(salt: Data(repeating: 0x04, count: 16), digest: Data(repeating: 0xA4, count: 32))
        var item1 = uniqueVaultItem().makeWritable()
        item1.killphraseUpdate = .set(d)
        let existing = try encode(sut: sut, item: item1)

        var item2 = uniqueVaultItem().makeWritable()
        item2.killphraseUpdate = .clear
        let existing2 = try encode(sut: sut, item: item2, existing: existing)

        #expect(existing2.killphraseSalt == nil)
        #expect(existing2.killphraseDigest == nil)
    }

    @Test
    func encodeMetadata_newItemEncodesEmptyTags() throws {
        let sut = makeSUT()
        let item = uniqueVaultItem(tags: []).makeWritable()

        let encoded = try encode(sut: sut, item: item)
        #expect(encoded.tags == [])
    }

    @Test
    func encodeMetadata_newItemEncodesSomeTags() throws {
        let id1 = UUID()
        let id2 = UUID()
        let sut = makeSUT()
        let item = uniqueVaultItem(tags: [.init(id: id1), .init(id: id2)]).makeWritable()

        let persisted1 = makePersistedTag(id: id1)
        let persisted2 = makePersistedTag(id: id2)
        let encoded = try encode(sut: sut, item: item)
        #expect(encoded.tags.map(\.id).reducedToSet() == [persisted1.id, persisted2.id])
    }

    @Test
    func encodeMetadata_existingItemEncodesEmptyTags() throws {
        let id1 = UUID()
        _ = makePersistedTag(id: id1)
        let sut = makeSUT()
        let item = uniqueVaultItem(tags: [.init(id: id1)]).makeWritable()
        let existing = try encode(sut: sut, item: item)

        let itemNew = uniqueVaultItem(tags: []).makeWritable()
        let encoded = try encode(sut: sut, item: itemNew, existing: existing)
        #expect(encoded.tags == [])
    }

    @Test
    func encodeMetadata_existingItemEncodesSomeTags() throws {
        let id1 = UUID()
        _ = makePersistedTag(id: id1)
        let sut = makeSUT()
        let item = uniqueVaultItem(tags: [.init(id: id1)]).makeWritable()
        let existing = try encode(sut: sut, item: item)

        let id2 = UUID()
        let persisted2 = makePersistedTag(id: id2)
        let itemNew = uniqueVaultItem(tags: [.init(id: id2)]).makeWritable()
        let encoded = try encode(sut: sut, item: itemNew, existing: existing)
        #expect(encoded.tags.map(\.id).reducedToSet() == [persisted2.id])
    }

    @Test
    func encodeLockState_newItemEncodesNotLocked() throws {
        let sut = makeSUT()
        let item = uniqueVaultItem(lockState: .notLocked).makeWritable()

        let encoded = try encode(sut: sut, item: item)

        #expect(encoded.lockState == "NOT_LOCKED")
    }

    @Test
    func encodeLockState_existingItemEncodesNotLocked() throws {
        let sut = makeSUT()
        let item = uniqueVaultItem(lockState: .lockedWithNativeSecurity).makeWritable()
        let existing = try encode(sut: sut, item: item)

        let newItem = uniqueVaultItem(lockState: .notLocked).makeWritable()
        let encoded = try encode(sut: sut, item: newItem, existing: existing)
        #expect(encoded.lockState == "NOT_LOCKED")
    }

    @Test
    func encodeLockState_newItemEncodesLockedNative() throws {
        let sut = makeSUT()
        let item = uniqueVaultItem(lockState: .lockedWithNativeSecurity).makeWritable()

        let encoded = try encode(sut: sut, item: item)

        #expect(encoded.lockState == "LOCKED_NATIVE")
    }

    @Test
    func encodeLockState_existingItemEncodesLockedNative() throws {
        let sut = makeSUT()
        let item = uniqueVaultItem(lockState: .notLocked).makeWritable()
        let existing = try encode(sut: sut, item: item)

        let newItem = uniqueVaultItem(lockState: .lockedWithNativeSecurity).makeWritable()
        let encoded = try encode(sut: sut, item: newItem, existing: existing)
        #expect(encoded.lockState == "LOCKED_NATIVE")
    }
}

// MARK: - OTP

extension PersistedVaultItemEncoderTests {
    @Test(arguments: [
        (OTPAuthDigits(value: 6), Int32(6)),
        (OTPAuthDigits(value: 7), Int32(7)),
        (OTPAuthDigits(value: 8), Int32(8)),
        (OTPAuthDigits(value: 12), Int32(12)),
        (OTPAuthDigits(value: 100), Int32(100)),
    ])
    func encodeOTP_digitsEncodesToInt32(digits: OTPAuthDigits, value: Int32) throws {
        let sut = makeSUT()
        let code = makeWritable(code: makeCodeValue(digits: digits))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.digits == value)
    }

    @Test
    func encodeOTP_authTypeEncodesKindTOTP() throws {
        let sut = makeSUT()
        let code = makeWritable(code: makeCodeValue(type: .totp()))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.authType == "totp")
    }

    @Test
    func encodeOTP_authTypeEncodesKindHOTP() throws {
        let sut = makeSUT()
        let code = makeWritable(code: makeCodeValue(type: .hotp()))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.authType == "hotp")
    }

    @Test
    func encodeOTP_periodForTOTP() throws {
        let sut = makeSUT()
        let code = makeWritable(code: makeCodeValue(type: .totp(period: 69)))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.period == 69)
    }

    @Test
    func encodeOTP_noPeriodForHOTP() throws {
        let sut = makeSUT()
        let code = makeWritable(code: makeCodeValue(type: .hotp()))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.period == nil)
    }

    @Test
    func encodeOTP_counterForHOTP() throws {
        let sut = makeSUT()
        let code = makeWritable(code: makeCodeValue(type: .hotp(counter: 69)))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.counter == 69)
    }

    @Test
    func encodeOTP_noCounterForTOTP() throws {
        let sut = makeSUT()
        let code = makeWritable(code: makeCodeValue(type: .totp()))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.counter == nil)
    }

    @Test
    func encodeOTP_accountName() throws {
        let sut = makeSUT()
        let accountName = UUID().uuidString
        let code = makeWritable(code: makeCodeValue(accountName: accountName))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.accountName == accountName)
    }

    @Test
    func encodeOTP_isser() throws {
        let sut = makeSUT()
        let issuer = UUID().uuidString
        let code = makeWritable(code: makeCodeValue(issuer: issuer))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.issuer == issuer)
    }

    @Test(arguments: [
        (OTPAuthAlgorithm.sha1, "SHA1"),
        (OTPAuthAlgorithm.sha256, "SHA256"),
        (OTPAuthAlgorithm.sha512, "SHA512"),
    ])
    func encodeOTP_algorithm(algo: OTPAuthAlgorithm, expected: String) throws {
        let sut = makeSUT()
        let code = makeWritable(code: makeCodeValue(algorithm: algo))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.algorithm == expected)
    }

    @Test(arguments: [(OTPAuthSecret.Format.base32, "BASE_32")])
    func encodeOTP_secretFormat(format: OTPAuthSecret.Format, expected: String) throws {
        let sut = makeSUT()
        let secret = OTPAuthSecret(data: Data(), format: format)
        let code = makeWritable(code: makeCodeValue(secret: secret))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.secretFormat == expected)
    }

    @Test
    func encodeOTP_secretToBinary() throws {
        let sut = makeSUT()
        let secretData = Data([0xFF, 0xEE, 0x66, 0x77, 0x22])
        let secret = OTPAuthSecret(data: secretData, format: .base32)
        let code = makeWritable(code: makeCodeValue(secret: secret))

        let encoded = try encode(sut: sut, item: code)
        #expect(encoded.otpDetails?.secretData == secretData)
    }
}

// MARK: - Secure Note

extension PersistedVaultItemEncoderTests {
    @Test
    func encodeNote_title() throws {
        let sut = makeSUT()
        let item = anySecureNote(title: "this is my title").wrapInAnyVaultItem().makeWritable()

        let encoded = try encode(sut: sut, item: item)
        #expect(encoded.noteDetails?.title == "this is my title")
    }

    @Test
    func encodeNote_contents() throws {
        let sut = makeSUT()
        let item = anySecureNote(contents: "this is the note contents").wrapInAnyVaultItem().makeWritable()

        let encoded = try encode(sut: sut, item: item)
        #expect(encoded.noteDetails?.contents == "this is the note contents")
    }
}

// MARK: - EncryptedItem

extension PersistedVaultItemEncoderTests {
    @Test
    func encodeEncryptedItem_correctly() throws {
        let sut = makeSUT()

        let itemData = Data.random(count: 16)
        let itemAuth = Data.random(count: 16)
        let itemEncryptionIV = Data.random(count: 16)
        let itemKeygenSalt = Data.random(count: 16)
        let itemKeygenSignature = "my sig"
        let item = EncryptedItem(
            version: "1.0.3",
            title: "this is cool",
            data: itemData,
            authentication: itemAuth,
            encryptionIV: itemEncryptionIV,
            keygenSalt: itemKeygenSalt,
            keygenSignature: itemKeygenSignature,
        ).wrapInAnyVaultItem().makeWritable()

        let encoded = try encode(sut: sut, item: item)

        let details = try #require(encoded.encryptedItemDetails)
        #expect(details.version == "1.0.3")
        #expect(details.title == "this is cool")
        #expect(details.data == itemData)
        #expect(details.authentication == itemAuth)
        #expect(details.encryptionIV == itemEncryptionIV)
        #expect(details.keygenSalt == itemKeygenSalt)
        #expect(details.keygenSignature == itemKeygenSignature)
    }
}

// MARK: - Recovery Phrase

extension PersistedVaultItemEncoderTests {
    @Test
    func encodeRecoveryPhrase_refusesPlaintext() throws {
        let sut = makeSUT()
        let item = VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))

        #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try sut.encode(item: item.makeWritable())
        }
        #expect(context.insertedModelsArray.isEmpty)
    }
}

// MARK: - Helpers

extension PersistedVaultItemEncoderTests {
    private func makeSUT(currentDate: @escaping () -> Date = { Date() }) -> PersistedVaultItemEncoder {
        PersistedVaultItemEncoder(context: context, currentDate: currentDate)
    }

    /// Encodes and adds to context, so we can resolve properties on the item.
    private func encode(
        sut: PersistedVaultItemEncoder,
        item: VaultItem.Write,
        existing: PersistedVaultItem? = nil,
    ) throws -> PersistedVaultItem {
        let encoded = try sut.encode(item: item, existing: existing)
        context.insert(encoded)
        return encoded
    }

    private func makePersistedTag(id: UUID = UUID(), title: String = "Any") -> PersistedVaultTag {
        let tag = PersistedVaultTag(id: id, title: title, color: nil, iconName: nil, items: [])
        context.insert(tag)
        return tag
    }

    private func makeWritable(
        relativeOrder: UInt64 = .min,
        userDescription: String = "",
        code: OTPAuthCode,
        color: VaultItemColor? = nil,
        visibility: VaultItemVisibility = .always,
        searchableLevel: VaultItemSearchableLevel = .full,
        tags: Set<Identifier<VaultItemTag>> = [],
        searchPassphraseUpdate: VaultItem.SearchPassphraseUpdate = .clear,
        killphraseUpdate: VaultItem.KillphraseUpdate = .clear,
        lockState: VaultItemLockState = .notLocked,
        showInQuickType: Bool = true,
        previewMode: NotePreviewMode = .titleAndFirstLine,
    ) -> VaultItem.Write {
        VaultItem.Write(
            relativeOrder: relativeOrder,
            userDescription: userDescription,
            color: color,
            item: .otpCode(code),
            tags: tags,
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphraseUpdate: searchPassphraseUpdate,
            killphraseUpdate: killphraseUpdate,
            lockState: lockState,
            showInQuickType: showInQuickType,
            previewMode: previewMode,
        )
    }

    private func makeCodeValue(
        type: OTPAuthType = .totp(),
        secret: OTPAuthSecret = .empty(),
        algorithm: OTPAuthAlgorithm = .default,
        digits: OTPAuthDigits = .default,
        accountName: String = "any",
        issuer: String = "",
    ) -> OTPAuthCode {
        OTPAuthCode(
            type: type,
            data: .init(
                secret: secret,
                algorithm: algorithm,
                digits: digits,
                accountName: accountName,
                issuer: issuer,
            ),
        )
    }
}
