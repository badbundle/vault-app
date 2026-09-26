import Foundation
import TestHelpers
import Testing
import VaultBackup
import VaultCore
@testable import VaultFeed

final class VaultBackupItemDecoderTests {
    // MARK: - Note

    @Test
    func decodeNote_decodesNote() throws {
        let id = UUID()
        let createdDate = Date()
        let updateDate = Date()
        let description = "my user description"
        let tag = UUID()
        let item = VaultBackupItem(
            id: id,
            createdDate: createdDate,
            updatedDate: updateDate,
            relativeOrder: 77777,
            userDescription: description,
            tags: [tag],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseSalt: anySearchPassphraseDigest.salt,
            searchPassphraseDigest: anySearchPassphraseDigest.digest,
            killphraseSalt: anyKillphraseDigest.salt,
            killphraseDigest: anyKillphraseDigest.digest,
            lockState: .notLocked,
            tintColor: .init(red: 0.1, green: 0.2, blue: 0.3),
            item: .note(data: .init(title: "title", rawContents: "contents", format: .markdown)),
        )
        let sut = makeSUT()

        let decodedItem = try sut.decode(backupItem: item)

        #expect(decodedItem.id.rawValue == id)
        #expect(decodedItem.metadata.created == createdDate)
        #expect(decodedItem.metadata.updated == updateDate)
        #expect(decodedItem.metadata.userDescription == description)
        #expect(decodedItem.metadata.visibility == .always)
        #expect(decodedItem.metadata.searchableLevel == .full)
        #expect(decodedItem.metadata.searchPassphrase == anySearchPassphraseDigest)
        #expect(decodedItem.metadata.killphrase == anyKillphraseDigest)
        #expect(decodedItem.metadata.color == .init(red: 0.1, green: 0.2, blue: 0.3))
        #expect(decodedItem.metadata.tags == [.init(id: tag)])
        #expect(decodedItem.metadata.lockState == .notLocked)
        #expect(decodedItem.metadata.relativeOrder == 77777)
        #expect(decodedItem.item.secureNote?.title == "title")
        #expect(decodedItem.item.secureNote?.contents == "contents")
        #expect(decodedItem.item.secureNote?.format == .markdown)

        #expect(decodedItem.item.encryptedItem == nil)
        #expect(decodedItem.item.otpCode == nil)
    }

    @Test(arguments: [true, false])
    func decode_decodesShowInQuickType(showInQuickType: Bool) throws {
        var item = anyOTPItem()
        item.showInQuickType = showInQuickType
        let sut = makeSUT()

        let decodedItem = try sut.decode(backupItem: item)

        #expect(decodedItem.metadata.showInQuickType == showInQuickType)
    }

    @Test
    func decode_decodesEveryPreviewMode() throws {
        let expected: [VaultBackupItem.PreviewMode: NotePreviewMode] = [
            .titleAndFirstLine: .titleAndFirstLine,
            .titleOnly: .titleOnly,
            .hidden: .hidden,
        ]
        let sut = makeSUT()

        for (backedUp, restored) in expected {
            var item = anyNoteItem()
            item.previewMode = backedUp
            let decodedItem = try sut.decode(backupItem: item)

            #expect(decodedItem.metadata.previewMode == restored, "\(backedUp) should restore")
        }
    }

    /// Backups made before these were recorded restore them as restoring always has: offered in QuickType, and
    /// previewing the title and first line.
    @Test
    func decode_backupWithoutQuickTypeOrPreviewModeRestoresAsBefore() throws {
        let item = anyNoteItem()
        #expect(item.showInQuickType == nil)
        #expect(item.previewMode == nil)
        let sut = makeSUT()

        let decodedItem = try sut.decode(backupItem: item)

        #expect(decodedItem.metadata.showInQuickType == true)
        #expect(decodedItem.metadata.previewMode == .titleAndFirstLine)
    }

    @Test
    func decodeNote_decodeswithNilContentsIntoEmptyString() throws {
        let item = anyNoteItem(contents: nil)
        let sut = makeSUT()

        let decodedItem = try sut.decode(backupItem: item)

        #expect(decodedItem.item.secureNote?.contents == "")
    }

    @Test
    func decode_legacyV2BackupDropsPlaintextSearchPassphrase() throws {
        // A vault backup created before V3 carried `searchPassphrase` as
        // a plaintext String. After V3, that field is gone from the
        // VaultBackupItem schema and Codable silently drops it. The
        // resulting model has no digest pair, which is the intended
        // failure mode: a pre-V3 backup is migrating into a model that
        // expects HMAC digests, and we accept data loss rather than
        // round-tripping the plaintext.
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "createdDate": 0,
            "updatedDate": 0,
            "relativeOrder": 0,
            "userDescription": "legacy",
            "tags": [],
            "visibility": "ALWAYS",
            "searchableLevel": "ONLY_PASSPHRASE",
            "searchPassphrase": "old-plaintext-passphrase",
            "lockState": "NOT_LOCKED",
            "item": {
                "note": {
                    "data": {
                        "title": "legacy note",
                        "format": "PLAIN"
                    }
                }
            },
            "obfuscationPadding": ""
        }
        """
        let data = Data(legacyJSON.utf8)
        let backupItem = try JSONDecoder().decode(VaultBackupItem.self, from: data)

        #expect(backupItem.searchPassphraseSalt == nil)
        #expect(backupItem.searchPassphraseDigest == nil)

        let sut = makeSUT()
        let decoded = try sut.decode(backupItem: backupItem)

        #expect(decoded.metadata.searchPassphrase == nil)
    }

    // MARK: - Encrypted Item

    @Test
    func decodeEncryptedItem_decodesEncryptedItem() throws {
        let id = UUID()
        let createdDate = Date()
        let updateDate = Date()
        let description = "my user description"
        let tag = UUID()
        let itemData = Data.random(count: 12)
        let itemAuthentication = Data.random(count: 12)
        let itemEncryptionIV = Data.random(count: 12)
        let itemKeygenSalt = Data.random(count: 12)
        let itemSignature = "this is sig"
        let encryptedItem = VaultBackupItem.Encrypted(
            version: "1.0.7",
            title: "this is my title",
            data: itemData,
            authentication: itemAuthentication,
            encryptionIV: itemEncryptionIV,
            keygenSalt: itemKeygenSalt,
            keygenSignature: itemSignature,
        )
        let item = VaultBackupItem(
            id: id,
            createdDate: createdDate,
            updatedDate: updateDate,
            relativeOrder: 77777,
            userDescription: description,
            tags: [tag],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseSalt: anySearchPassphraseDigest.salt,
            searchPassphraseDigest: anySearchPassphraseDigest.digest,
            killphraseSalt: anyKillphraseDigest.salt,
            killphraseDigest: anyKillphraseDigest.digest,
            lockState: .notLocked,
            tintColor: .init(red: 0.1, green: 0.2, blue: 0.3),
            item: .encrypted(data: encryptedItem),
        )
        let sut = makeSUT()

        let decodedItem = try sut.decode(backupItem: item)

        #expect(decodedItem.id.rawValue == id)
        #expect(decodedItem.metadata.created == createdDate)
        #expect(decodedItem.metadata.updated == updateDate)
        #expect(decodedItem.metadata.userDescription == description)
        #expect(decodedItem.metadata.visibility == .always)
        #expect(decodedItem.metadata.searchableLevel == .full)
        #expect(decodedItem.metadata.searchPassphrase == anySearchPassphraseDigest)
        #expect(decodedItem.metadata.killphrase == anyKillphraseDigest)
        #expect(decodedItem.metadata.color == .init(red: 0.1, green: 0.2, blue: 0.3))
        #expect(decodedItem.metadata.tags == [.init(id: tag)])
        #expect(decodedItem.metadata.lockState == .notLocked)
        #expect(decodedItem.metadata.relativeOrder == 77777)
        #expect(decodedItem.item.encryptedItem?.version == "1.0.7")
        #expect(decodedItem.item.encryptedItem?.title == "this is my title")
        #expect(decodedItem.item.encryptedItem?.data == itemData)
        #expect(decodedItem.item.encryptedItem?.authentication == itemAuthentication)
        #expect(decodedItem.item.encryptedItem?.encryptionIV == itemEncryptionIV)
        #expect(decodedItem.item.encryptedItem?.keygenSalt == itemKeygenSalt)
        #expect(decodedItem.item.encryptedItem?.keygenSignature == itemSignature)

        #expect(decodedItem.item.secureNote == nil)
        #expect(decodedItem.item.otpCode == nil)
    }

    // MARK: - OTP Code

    @Test
    func decodeOTP_decodesTOTPCode() throws {
        let id = UUID()
        let createdDate = Date()
        let updateDate = Date()
        let description = "my user description"
        let item = VaultBackupItem(
            id: id,
            createdDate: createdDate,
            updatedDate: updateDate,
            relativeOrder: 1234,
            userDescription: description,
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseSalt: anySearchPassphraseDigest.salt,
            searchPassphraseDigest: anySearchPassphraseDigest.digest,
            killphraseSalt: anyKillphraseDigest.salt,
            killphraseDigest: anyKillphraseDigest.digest,
            lockState: .lockedWithNativeSecurity,
            tintColor: .init(red: 0.1, green: 0.2, blue: 0.3),
            item: .otp(data: .init(
                secretFormat: "BASE_32",
                secretData: Data(hex: "ababababa"),
                authType: "totp",
                period: 30,
                counter: nil,
                algorithm: "SHA1",
                digits: 5,
                accountName: "my acc",
                issuer: "my iss",
            )),
        )
        let sut = makeSUT()

        let decodedItem = try sut.decode(backupItem: item)

        let expectedSecret = OTPAuthSecret(data: Data(hex: "ababababa"), format: .base32)
        #expect(decodedItem.id.rawValue == id)
        #expect(decodedItem.metadata.created == createdDate)
        #expect(decodedItem.metadata.updated == updateDate)
        #expect(decodedItem.metadata.userDescription == description)
        #expect(decodedItem.metadata.searchableLevel == .full)
        #expect(decodedItem.metadata.searchPassphrase == anySearchPassphraseDigest)
        #expect(decodedItem.metadata.killphrase == anyKillphraseDigest)
        #expect(decodedItem.metadata.visibility == .always)
        #expect(decodedItem.metadata.color == .init(red: 0.1, green: 0.2, blue: 0.3))
        #expect(decodedItem.metadata.lockState == .lockedWithNativeSecurity)
        #expect(decodedItem.metadata.relativeOrder == 1234)
        #expect(decodedItem.item.otpCode?.type == .totp(period: 30))
        #expect(decodedItem.item.otpCode?.data.secret == expectedSecret)
        #expect(decodedItem.item.otpCode?.data.accountName == "my acc")
        #expect(decodedItem.item.otpCode?.data.issuer == "my iss")
        #expect(decodedItem.item.otpCode?.data.digits == OTPAuthDigits(value: 5))
        #expect(decodedItem.item.otpCode?.data.algorithm == .sha1)

        #expect(decodedItem.item.encryptedItem == nil)
        #expect(decodedItem.item.secureNote == nil)
    }

    @Test
    func decodeOTP_decodesHOTPCode() throws {
        let id = UUID()
        let createdDate = Date()
        let updateDate = Date()
        let description = "my user description"
        let item = VaultBackupItem(
            id: id,
            createdDate: createdDate,
            updatedDate: updateDate,
            relativeOrder: 4321,
            userDescription: description,
            tags: [],
            visibility: .onlySearch,
            searchableLevel: .full,
            searchPassphraseSalt: anySearchPassphraseDigest.salt,
            searchPassphraseDigest: anySearchPassphraseDigest.digest,
            killphraseSalt: anyKillphraseDigest.salt,
            killphraseDigest: anyKillphraseDigest.digest,
            lockState: .notLocked,
            tintColor: .init(red: 0.2, green: 0.2, blue: 0.3),
            item: .otp(data: .init(
                secretFormat: "BASE_32",
                secretData: Data(hex: "ababababaff"),
                authType: "hotp",
                period: nil,
                counter: 10,
                algorithm: "SHA1",
                digits: 7,
                accountName: "my acc a",
                issuer: "my iss a",
            )),
        )
        let sut = makeSUT()

        let decodedItem = try sut.decode(backupItem: item)

        let expectedSecret = OTPAuthSecret(data: Data(hex: "ababababaff"), format: .base32)
        #expect(decodedItem.id.rawValue == id)
        #expect(decodedItem.metadata.created == createdDate)
        #expect(decodedItem.metadata.updated == updateDate)
        #expect(decodedItem.metadata.relativeOrder == 4321)
        #expect(decodedItem.metadata.userDescription == description)
        #expect(decodedItem.metadata.searchableLevel == .full)
        #expect(decodedItem.metadata.visibility == .onlySearch)
        #expect(decodedItem.metadata.searchPassphrase == anySearchPassphraseDigest)
        #expect(decodedItem.metadata.killphrase == anyKillphraseDigest)
        #expect(decodedItem.metadata.color == .init(red: 0.2, green: 0.2, blue: 0.3))
        #expect(decodedItem.metadata.lockState == .notLocked)
        #expect(decodedItem.item.otpCode?.type == .hotp(counter: 10))
        #expect(decodedItem.item.otpCode?.data.secret == expectedSecret)
        #expect(decodedItem.item.otpCode?.data.accountName == "my acc a")
        #expect(decodedItem.item.otpCode?.data.issuer == "my iss a")
        #expect(decodedItem.item.otpCode?.data.digits == OTPAuthDigits(value: 7))
        #expect(decodedItem.item.otpCode?.data.algorithm == .sha1)

        #expect(decodedItem.item.encryptedItem == nil)
        #expect(decodedItem.item.secureNote == nil)
    }

    @Test
    func decodeOTP_succeedsForAnyOTPItem() throws {
        // Checks that 'anyOTPItem' has a valid item, to ensure the throwing tests are correct.
        let otp = anyOTPItem()
        let sut = makeSUT()

        #expect(throws: Never.self) {
            try sut.decode(backupItem: otp)
        }
    }

    @Test
    func decodeOTP_failsToDecodesAlgorithms() throws {
        let otp_sha1 = anyOTPItem(algorithm: "SHA1")
        let item_sha1 = try makeSUT().decode(backupItem: otp_sha1)
        #expect(item_sha1.item.otpCode?.data.algorithm == .sha1)

        let otp_sha256 = anyOTPItem(algorithm: "SHA256")
        let item_sha256 = try makeSUT().decode(backupItem: otp_sha256)
        #expect(item_sha256.item.otpCode?.data.algorithm == .sha256)

        let otp_sha512 = anyOTPItem(algorithm: "SHA512")
        let item_sha512 = try makeSUT().decode(backupItem: otp_sha512)
        #expect(item_sha512.item.otpCode?.data.algorithm == .sha512)
    }

    @Test
    func decodeOTP_failsForInvalidType() throws {
        let otp = anyOTPItem(type: "inv")
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(backupItem: otp)
        }
    }

    @Test
    func decodeOTP_failsToDecodeTOTPIfNoPeriod() throws {
        let otp = anyOTPItem(type: "totp", period: nil)
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(backupItem: otp)
        }
    }

    @Test
    func decodeOTP_failsToDecodeHOTPIfNoCounter() throws {
        let otp = anyOTPItem(type: "hotp", counter: nil)
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(backupItem: otp)
        }
    }

    @Test
    func decodeOTP_failsToDecodeInvalidSecretFormat() throws {
        let otp = anyOTPItem(secretFormat: "inv")
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(backupItem: otp)
        }
    }

    @Test
    func decodeOTP_failsToDecodeInvalidAlgorithm() throws {
        let otp = anyOTPItem(algorithm: "inv")
        let sut = makeSUT()

        #expect(throws: (any Error).self) {
            try sut.decode(backupItem: otp)
        }
    }
}

// MARK: - Helpers

extension VaultBackupItemDecoderTests {
    private func makeSUT() -> VaultBackupItemDecoder {
        VaultBackupItemDecoder()
    }

    private func anyNoteItem(contents: String? = nil) -> VaultBackupItem {
        let id = UUID()
        let createdDate = Date()
        let updateDate = Date()
        let description = "my user description"
        return VaultBackupItem(
            id: id,
            createdDate: createdDate,
            updatedDate: updateDate,
            relativeOrder: .min,
            userDescription: description,
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseSalt: anySearchPassphraseDigest.salt,
            searchPassphraseDigest: anySearchPassphraseDigest.digest,
            killphraseSalt: anyKillphraseDigest.salt,
            killphraseDigest: anyKillphraseDigest.digest,
            lockState: .notLocked,
            tintColor: .init(red: 0.1, green: 0.2, blue: 0.3),
            item: .note(data: .init(title: "title", rawContents: contents, format: .markdown)),
        )
    }

    private func anyOTPItem(
        type: String = "totp",
        period: UInt64? = 30,
        counter: UInt64? = 0,
        secretFormat: String = "BASE_32",
        algorithm: String = "SHA1",
    ) -> VaultBackupItem {
        let createdDate = Date()
        let updateDate = Date()
        let description = "my user description"
        return VaultBackupItem(
            id: UUID(),
            createdDate: createdDate,
            updatedDate: updateDate,
            relativeOrder: .min,
            userDescription: description,
            tags: [],
            visibility: .onlySearch,
            searchableLevel: .full,
            searchPassphraseSalt: anySearchPassphraseDigest.salt,
            searchPassphraseDigest: anySearchPassphraseDigest.digest,
            killphraseSalt: anyKillphraseDigest.salt,
            killphraseDigest: anyKillphraseDigest.digest,
            lockState: .notLocked,
            tintColor: .init(red: 0.2, green: 0.2, blue: 0.3),
            item: .otp(data: .init(
                secretFormat: secretFormat,
                secretData: Data(hex: "ababababaff"),
                authType: type,
                period: period,
                counter: counter,
                algorithm: algorithm,
                digits: 7,
                accountName: "my acc a",
                issuer: "my iss a",
            )),
        )
    }
}

private let anyKillphraseDigest = KillphraseDigest(
    salt: Data(repeating: 0x11, count: 16),
    digest: Data(repeating: 0x22, count: 32),
)

private let anySearchPassphraseDigest = SearchPassphraseDigest(
    salt: Data(repeating: 0x33, count: 16),
    digest: Data(repeating: 0x44, count: 32),
)
