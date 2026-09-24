import Foundation
import Testing
@testable import VaultBackup

struct IntermediateEncodedVaultDecoderTests {
    let sut = IntermediateEncodedVaultDecoder()

    @Test
    func decodeVault_throwsForEmptyData() {
        let data = Data()
        let vault = IntermediateEncodedVault(data: data)

        #expect(throws: (any Error).self, performing: {
            try sut.decode(encodedVault: vault)
        })
    }

    @Test
    func decodeVault_throwsForInvalidJSON() {
        let data = Data("{}".utf8)
        let vault = IntermediateEncodedVault(data: data)

        #expect(throws: (any Error).self) {
            try sut.decode(encodedVault: vault)
        }
    }

    @Test
    func decodeVault_decodesZeroItems() throws {
        let input = VaultBackupPayload(
            version: "1.0.0",
            created: Date(timeIntervalSince1970: 1_700_575_468),
            userDescription: "my description",
            tags: [],
            items: [],
            obfuscationPadding: Data(),
        )
        let encoder = IntermediateEncodedVaultEncoder()

        let decoded = try sut.decode(encodedVault: encoder.encode(vaultBackup: input))

        #expect(decoded == input, "Decoded backup differs from input")
    }

    @Test
    func decodeVault_decodesNonZeroItems() throws {
        let date1 = Date(timeIntervalSince1970: 12345)
        let uuid1 = try #require(UUID(uuidString: "A5950174-2106-4251-BD73-58B8D39F77F3"))
        let item1 = VaultBackupItem(
            id: uuid1,
            createdDate: date1,
            updatedDate: date1.addingTimeInterval(1234),
            relativeOrder: .min,
            userDescription: "",
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseSalt: Data(repeating: 0x33, count: 16),
            searchPassphraseDigest: Data(repeating: 0x44, count: 32),
            killphraseSalt: nil,
            killphraseDigest: nil,
            lockState: .lockedWithNativeSecurity,
            item: .note(data: .init(title: "Hello world", rawContents: "contents of note", format: .plain)),
        )
        let date2 = Date(timeIntervalSince1970: 45658)
        let uuid2 = try #require(UUID(uuidString: "29808EAD-3727-4FF6-9B01-C5506BBDC409"))
        let item2 = VaultBackupItem(
            id: uuid2,
            createdDate: date2,
            updatedDate: date2.addingTimeInterval(1234),
            relativeOrder: 100,
            userDescription: "",
            tags: [],
            visibility: .always,
            searchableLevel: .none,
            searchPassphraseSalt: nil,
            searchPassphraseDigest: nil,
            killphraseSalt: nil,
            killphraseDigest: nil,
            lockState: .notLocked,
            item: .note(data: .init(title: "Hello world again", rawContents: nil, format: .markdown)),
        )
        let date3 = Date(timeIntervalSince1970: 345_652_348)
        let uuid3 = try #require(UUID(uuidString: "EF0849B7-C070-491B-A31B-51A11AEA26F4"))
        let item3 = VaultBackupItem(
            id: uuid3,
            createdDate: date3,
            updatedDate: date3.addingTimeInterval(100),
            relativeOrder: 999,
            userDescription: "",
            tags: [],
            visibility: .onlySearch,
            searchableLevel: .onlyTitle,
            searchPassphraseSalt: Data(repeating: 0x33, count: 16),
            searchPassphraseDigest: Data(repeating: 0x44, count: 32),
            killphraseSalt: nil,
            killphraseDigest: nil,
            lockState: .lockedWithNativeSecurity,
            item: .otp(data: .init(
                secretFormat: "any",
                secretData: Data(repeating: 0xFE, count: 20),
                authType: "authtype",
                period: 123,
                counter: 456,
                algorithm: "algo",
                digits: 789,
                accountName: "acc",
                issuer: "iss",
            )),
        )
        let input = anyBackupPayload(
            created: date1,
            userDescription: "my description again",
            items: [item1, item2, item3],
        )
        let encoder = IntermediateEncodedVaultEncoder()

        let decoded = try sut.decode(encodedVault: encoder.encode(vaultBackup: input))

        #expect(decoded == input, "Decoded backup differs from input")
    }

    @Test
    func decodeVault_decodesEncryptedItem() throws {
        let input = try anyBackupPayload(created: Date(timeIntervalSince1970: 12345), items: [anyEncryptedBackupItem()])
        let encoder = IntermediateEncodedVaultEncoder()

        let decoded = try sut.decode(encodedVault: encoder.encode(vaultBackup: input))

        #expect(decoded == input, "Decoded backup differs from input")
    }

    /// The format backups with encrypted items have always been written in, which must still restore.
    @Test
    func decodeVault_decodesEncryptedItemInExistingFormat() throws {
        let json = """
        {
          "created" : 12345000,
          "items" : [
            {
              "created_date" : 12345000,
              "id" : "A5950174-2106-4251-BD73-58B8D39F77F3",
              "item" : {
                "encrypted" : {
                  "data" : {
                    "authentication" : "AgICAgICAgICAgICAgICAgI=",
                    "data" : "/v7+/v7+",
                    "encryption_iv" : "BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE",
                    "keygen_salt" : "BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUF",
                    "keygen_signature" : "this is test sig",
                    "title" : "this is my title",
                    "version" : "2.0.3"
                  }
                }
              },
              "lock_state" : "LOCKED_NATIVE",
              "relative_order" : 1000,
              "searchable_level" : "FULL",
              "tags" : [],
              "updated_date" : 19345000,
              "user_description" : "",
              "visibility" : "ALWAYS"
            }
          ],
          "obfuscation_padding" : "q6urCg==",
          "tags" : [],
          "user_description" : "Example vault with a single encrypted item",
          "version" : "1.0.0"
        }
        """
        let compressed = try (Data(json.utf8) as NSData).compressed(using: .lzma) as Data

        let decoded = try sut.decode(encodedVault: IntermediateEncodedVault(data: compressed))

        let item = try #require(decoded.items.first)
        guard case let .encrypted(data: encrypted) = item.item else {
            Issue.record("Expected an encrypted item, got \(item.item)")
            return
        }
        #expect(encrypted.encryptionIV == Data(repeating: 0x04, count: 24))
        #expect(encrypted.data == Data(repeating: 0xFE, count: 6))
        #expect(encrypted.authentication == Data(repeating: 0x02, count: 17))
        #expect(encrypted.keygenSalt == Data(repeating: 0x05, count: 30))
        #expect(encrypted.keygenSignature == "this is test sig")
        #expect(encrypted.title == "this is my title")
        #expect(encrypted.version == "2.0.3")
        #expect(item.lockState == .lockedWithNativeSecurity)
    }
}

// MARK: - Helpers

extension IntermediateEncodedVaultDecoderTests {
    private func anyEncryptedBackupItem() throws -> VaultBackupItem {
        try VaultBackupItem(
            id: #require(UUID(uuidString: "A5950174-2106-4251-BD73-58B8D39F77F3")),
            createdDate: Date(timeIntervalSince1970: 12345),
            updatedDate: Date(timeIntervalSince1970: 19345),
            relativeOrder: 1000,
            userDescription: "",
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseSalt: nil,
            searchPassphraseDigest: nil,
            killphraseSalt: nil,
            killphraseDigest: nil,
            lockState: .lockedWithNativeSecurity,
            item: .encrypted(data: .init(
                version: "1.0.0",
                title: "this is my title",
                data: Data(repeating: 0xFE, count: 300),
                authentication: Data(repeating: 0x02, count: 17),
                encryptionIV: Data(repeating: 0x04, count: 24),
                keygenSalt: Data(repeating: 0x05, count: 30),
                keygenSignature: "this is test sig",
            )),
        )
    }

    private func anyBackupPayload(
        created: Date = Date(),
        userDescription: String = "my description",
        tags: [VaultBackupTag] = [],
        items: [VaultBackupItem] = [],
    ) -> VaultBackupPayload {
        VaultBackupPayload(
            version: "1.0.0",
            created: created,
            userDescription: userDescription,
            tags: tags,
            items: items,
            obfuscationPadding: Data(),
        )
    }
}
