import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

@MainActor
struct RecoveryPhraseEncryptableTests {
    // MARK: - Container

    @Test(arguments: recoveryPhraseFixtures)
    func encryptedContainer_roundTripsExactly(phrase: RecoveryPhrase) throws {
        let container = try phrase.makeEncryptedContainer()

        #expect(container.itemIdentifier == VaultIdentifiers.Item.recoveryPhrase)
        #expect(container.title == phrase.title)
        expectExactlyEqual(RecoveryPhrase(encryptedContainer: container), phrase)
    }

    @Test(arguments: recoveryPhraseFixtures)
    func encryptedContainer_roundTripsExactlyThroughJSON(phrase: RecoveryPhrase) throws {
        let encoded = try testEncoder().encode(phrase.makeEncryptedContainer())
        let decoded = try testDecoder().decode(RecoveryPhrase.EncryptedContainer.self, from: encoded)

        expectExactlyEqual(RecoveryPhrase(encryptedContainer: decoded), phrase)
    }

    @Test
    func encryptedContainer_encodedFormat() throws {
        let phrase = RecoveryPhrase(
            title: "Hello world",
            words: ["abandon", "ability", "able"],
            standard: .slip39,
            passphrase: "passphrase",
            contents: "Some contents",
        )

        let container = try phrase.makeEncryptedContainer()
        let encodedContainer = try testEncoder().encode(container)

        let string = try #require(String(data: encodedContainer, encoding: .utf8))
        assertSnapshot(of: string, as: .lines)
    }

    @Test(arguments: [
        (RecoveryPhraseStandard.bip39, "BIP39"),
        (.slip39, "SLIP39"),
        (.electrum, "ELECTRUM"),
        (.monero, "MONERO"),
        (.other, "OTHER"),
    ])
    func encryptedContainer_encodesStandard(standard: RecoveryPhraseStandard, expected: String) throws {
        let phrase = anyRecoveryPhrase(standard: standard)

        let json = try encodedJSONObject(phrase.makeEncryptedContainer())

        #expect(json["standard"] as? String == expected)
    }

    @Test(arguments: [
        ("BIP39", RecoveryPhraseStandard.bip39),
        ("SLIP39", .slip39),
        ("ELECTRUM", .electrum),
        ("MONERO", .monero),
        ("OTHER", .other),
        // Unknown, from a later version, or not the exact case.
        ("SOME_FUTURE_STANDARD", .other),
        ("bip39", .other),
        ("", .other),
    ])
    func decode_standard(rawValue: String, expected: RecoveryPhraseStandard) throws {
        let json = """
        {
          "item_identifier" : "vault.item.recovery-phrase.v1",
          "contents" : "",
          "passphrase" : "",
          "standard" : "\(rawValue)",
          "title" : "Title",
          "words" : ["one", "two"]
        }
        """

        let container = try testDecoder().decode(RecoveryPhrase.EncryptedContainer.self, from: Data(json.utf8))
        let phrase = RecoveryPhrase(encryptedContainer: container)

        #expect(phrase.standard == expected)
        #expect(phrase.words == ["one", "two"], "The words are never lost, even if the standard isn't known")
    }

    @Test
    func encryptedContainer_encodesWordsInOrder() throws {
        let words = ["zoo", "abandon", "wrong", "zoo", "able"]
        let phrase = anyRecoveryPhrase(words: words, standard: .other)

        let json = try encodedJSONObject(phrase.makeEncryptedContainer())

        #expect(json["words"] as? [String] == words)
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
        #expect(phrase.contents == "")
        #expect(phrase.words == ["one", "two"])
    }

    @Test
    func decode_ignoresUnknownFields() throws {
        let json = """
        {
          "item_identifier" : "vault.item.recovery-phrase.v1",
          "some_future_field" : { "nested" : true },
          "standard" : "BIP39",
          "title" : "Title",
          "words" : ["one"]
        }
        """

        let container = try testDecoder().decode(RecoveryPhrase.EncryptedContainer.self, from: Data(json.utf8))

        #expect(RecoveryPhrase(encryptedContainer: container).words == ["one"])
    }

    @Test(arguments: [
        // No words.
        #"{ "item_identifier" : "vault.item.recovery-phrase.v1", "title" : "Title" }"#,
        // No title.
        #"{ "item_identifier" : "vault.item.recovery-phrase.v1", "words" : ["one"] }"#,
        // No identifier.
        #"{ "title" : "Title", "words" : ["one"] }"#,
        // Words aren't a list of strings.
        #"{ "item_identifier" : "vault.item.recovery-phrase.v1", "title" : "Title", "words" : "one two" }"#,
        #"{ "item_identifier" : "vault.item.recovery-phrase.v1", "title" : "Title", "words" : [1, 2] }"#,
        // Wrong types for optional fields fail rather than silently dropping data.
        #"{ "item_identifier" : "vault.item.recovery-phrase.v1", "title" : "T", "words" : ["one"], "contents" : 5 }"#,
        #"{ "item_identifier" : "vault.item.recovery-phrase.v1", "title" : "T", "words" : ["one"], "passphrase" : [] }"#,
    ])
    func decode_malformedContainerThrows(json: String) {
        #expect(throws: DecodingError.self) {
            try testDecoder().decode(RecoveryPhrase.EncryptedContainer.self, from: Data(json.utf8))
        }
    }

    // MARK: - Encryption

    @Test(arguments: recoveryPhraseFixtures)
    func encryptAndDecrypt_roundTripsExactly(phrase: RecoveryPhrase) throws {
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")

        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: phrase)
        let decryptor = VaultItemDecryptor(key: key)

        #expect(encrypted.title == phrase.title)
        #expect(try decryptor.decryptItemIdentifier(item: encrypted) == VaultIdentifiers.Item.recoveryPhrase)
        let decrypted: RecoveryPhrase = try decryptor.decrypt(
            item: encrypted,
            expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
        )
        expectExactlyEqual(decrypted, phrase)
    }

    @Test(arguments: recoveryPhraseFixtures)
    func encrypt_onlyTheTitleIsInPlaintext(phrase: RecoveryPhrase) throws {
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")

        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: phrase)
        let encoded = try JSONEncoder().encode(encrypted)
        let string = try #require(String(data: encoded, encoding: .utf8))

        // Short words could turn up in the base64 ciphertext by chance, so only check the longer ones, and the
        // phrase as a whole.
        for word in phrase.words where word.count >= 5 {
            #expect(!string.contains(word), "A word is visible without decrypting")
        }
        #expect(!string.contains(phrase.words.joined(separator: " ")))
        if phrase.passphrase.isNotBlank {
            #expect(!string.contains(phrase.passphrase))
        }
        if phrase.contents.isNotBlank {
            #expect(!string.contains(phrase.contents))
        }
        #expect(!string.contains(VaultIdentifiers.Item.recoveryPhrase), "The item type is visible without decrypting")
    }

    @Test
    func encrypt_usesDifferentCiphertextEachTime() throws {
        let phrase = anyRecoveryPhrase()
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")
        let encryptor = VaultItemEncryptor(key: key)

        let first = try encryptor.encrypt(item: phrase)
        let second = try encryptor.encrypt(item: phrase)

        #expect(first.encryptionIV != second.encryptionIV)
        #expect(first.data != second.data)
    }

    @Test
    func decrypt_wrongPasswordFails() throws {
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")
        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: anyRecoveryPhrase())
        let wrongKey = try VaultKeyDeriver.testing.recreateEncryptionKey(password: "wrong", salt: key.salt)

        let error = #expect(throws: VaultItemDecryptor.Error.self) {
            let _: RecoveryPhrase = try VaultItemDecryptor(key: wrongKey).decrypt(
                item: encrypted,
                expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
            )
        }
        guard case .decryptionFailed = error else {
            Issue.record("Expected .decryptionFailed, got \(String(describing: error))")
            return
        }
    }

    @Test
    func decrypt_tamperedCiphertextFails() throws {
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")
        var encrypted = try VaultItemEncryptor(key: key).encrypt(item: anyRecoveryPhrase())
        encrypted.data[encrypted.data.startIndex] ^= 0x01

        let error = #expect(throws: VaultItemDecryptor.Error.self) {
            let _: RecoveryPhrase = try VaultItemDecryptor(key: key).decrypt(
                item: encrypted,
                expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
            )
        }
        guard case .decryptionFailed = error else {
            Issue.record("Expected .decryptionFailed, got \(String(describing: error))")
            return
        }
    }

    @Test
    func decrypt_recoveryPhraseIsNotASecureNote() throws {
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")
        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: anyRecoveryPhrase())

        let error = #expect(throws: VaultItemDecryptor.Error.self) {
            let _: SecureNote = try VaultItemDecryptor(key: key).decrypt(
                item: encrypted,
                expectedItemIdentifier: VaultIdentifiers.Item.secureNote,
            )
        }
        guard case .mismatchedItemIdentifier = error else {
            Issue.record("Expected .mismatchedItemIdentifier, got \(String(describing: error))")
            return
        }
    }

    @Test
    func decrypt_secureNoteIsNotARecoveryPhrase() throws {
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")
        let note = SecureNote(title: "Title", contents: "abandon ability able", format: .plain)
        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: note)

        let error = #expect(throws: VaultItemDecryptor.Error.self) {
            let _: RecoveryPhrase = try VaultItemDecryptor(key: key).decrypt(
                item: encrypted,
                expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
            )
        }
        guard case .mismatchedItemIdentifier = error else {
            Issue.record("Expected .mismatchedItemIdentifier, got \(String(describing: error))")
            return
        }
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

    private func encodedJSONObject(_ container: RecoveryPhrase.EncryptedContainer) throws -> [String: Any] {
        let data = try testEncoder().encode(container)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// Checks that two phrases are identical down to the Unicode scalars, rather than only canonically equivalent (which
/// is what `String`'s `==` checks).
func expectExactlyEqual(
    _ actual: RecoveryPhrase,
    _ expected: RecoveryPhrase,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    func scalars(_ string: String) -> [UInt32] {
        string.unicodeScalars.map(\.value)
    }

    #expect(actual.standard == expected.standard, sourceLocation: sourceLocation)
    #expect(scalars(actual.title) == scalars(expected.title), sourceLocation: sourceLocation)
    #expect(actual.words.map(scalars) == expected.words.map(scalars), sourceLocation: sourceLocation)
    #expect(scalars(actual.passphrase) == scalars(expected.passphrase), sourceLocation: sourceLocation)
    #expect(scalars(actual.contents) == scalars(expected.contents), sourceLocation: sourceLocation)
}
