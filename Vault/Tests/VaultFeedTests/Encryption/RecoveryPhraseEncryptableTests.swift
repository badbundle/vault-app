import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

@MainActor
struct RecoveryPhraseEncryptableTests {
    @Test(arguments: RecoveryPhraseStandard.allCases)
    func encryptedContainer_roundTrips(standard: RecoveryPhraseStandard) throws {
        let phrase = RecoveryPhrase(
            title: "My wallet",
            words: ["abandon", "ability", "able"],
            standard: standard,
            passphrase: " spaced passphrase ",
        )

        let container = try phrase.makeEncryptedContainer()

        #expect(container.itemIdentifier == VaultIdentifiers.Item.recoveryPhrase)
        #expect(container.title == "My wallet")
        #expect(RecoveryPhrase(encryptedContainer: container) == phrase)
    }

    @Test
    func encryptedContainer_encodedFormat() throws {
        let phrase = RecoveryPhrase(
            title: "Hello world",
            words: ["abandon", "ability", "able"],
            standard: .slip39,
            passphrase: "passphrase",
        )

        let container = try phrase.makeEncryptedContainer()
        let encodedContainer = try testEncoder().encode(container)

        let string = try #require(String(data: encodedContainer, encoding: .utf8))
        assertSnapshot(of: string, as: .lines)
    }

    @Test
    func decode_unknownStandardIsOther() throws {
        let json = """
        {
          "item_identifier" : "vault.item.recovery-phrase.v1",
          "passphrase" : "",
          "standard" : "SOME_FUTURE_STANDARD",
          "title" : "Title",
          "words" : ["one", "two"]
        }
        """

        let container = try testDecoder().decode(RecoveryPhrase.EncryptedContainer.self, from: Data(json.utf8))
        let phrase = RecoveryPhrase(encryptedContainer: container)

        #expect(phrase.standard == .other)
        #expect(phrase.words == ["one", "two"])
    }

    @Test
    func decode_missingOptionalFieldsUseDefaults() throws {
        let json = """
        {
          "item_identifier" : "vault.item.recovery-phrase.v1",
          "title" : "Title",
          "words" : ["one", "two"]
        }
        """

        let container = try testDecoder().decode(RecoveryPhrase.EncryptedContainer.self, from: Data(json.utf8))
        let phrase = RecoveryPhrase(encryptedContainer: container)

        #expect(phrase.standard == .other)
        #expect(phrase.passphrase == "")
    }

    @Test
    func encryptAndDecrypt_roundTrips() throws {
        let phrase = anyRecoveryPhrase(title: "Title", passphrase: "extra")
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")

        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: phrase)
        let decryptor = VaultItemDecryptor(key: key)

        #expect(encrypted.title == "Title")
        #expect(try decryptor.decryptItemIdentifier(item: encrypted) == VaultIdentifiers.Item.recoveryPhrase)
        let decrypted: RecoveryPhrase = try decryptor.decrypt(
            item: encrypted,
            expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
        )
        #expect(decrypted == phrase)
    }

    @Test
    func encrypt_doesNotContainWordsInPlaintext() throws {
        let phrase = anyRecoveryPhrase(title: "Title", passphrase: "secret passphrase")
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")

        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: phrase)
        let encoded = try JSONEncoder().encode(encrypted)
        let string = try #require(String(data: encoded, encoding: .utf8))

        #expect(!string.contains("abandon"))
        #expect(!string.contains("secret passphrase"))
    }
}

// MARK: - Helpers

extension RecoveryPhraseEncryptableTests {
    /// Encodes into a test format, actual prod encoding may differ.
    private func testEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dataEncodingStrategy = .base64
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    private func testDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
