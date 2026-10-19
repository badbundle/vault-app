import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

@MainActor
struct PrivateKeyEncryptableTests {
    @Test(arguments: privateKeyFixtures)
    func encryptedContainer_roundTripsExactly(key: PrivateKey) throws {
        let container = try key.makeEncryptedContainer()

        #expect(container.itemIdentifier == VaultIdentifiers.Item.privateKey)
        #expect(container.title == key.title)
        expectExactlyEqual(PrivateKey(encryptedContainer: container), key)
    }

    @Test(arguments: privateKeyFixtures)
    func encryptedContainer_roundTripsExactlyThroughJSON(key: PrivateKey) throws {
        let encoded = try testEncoder().encode(key.makeEncryptedContainer())
        let decoded = try testDecoder().decode(PrivateKey.EncryptedContainer.self, from: encoded)

        expectExactlyEqual(PrivateKey(encryptedContainer: decoded), key)
    }

    /// The stored format, which never changes once released (G67). The key's format isn't stored: it's recognized
    /// each time.
    @Test
    func encryptedContainer_encodedFormat() throws {
        let key = PrivateKey(title: "Hello world", key: validWIFKey, contents: "Some contents")

        let encoded = try testEncoder().encode(key.makeEncryptedContainer())

        #expect(String(decoding: encoded, as: UTF8.self) == """
        {
          "contents" : "Some contents",
          "item_identifier" : "vault.item.private-key.v1",
          "key" : "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617",
          "title" : "Hello world"
        }
        """)
    }

    /// A description a later version drops still leaves the key, so it's never lost.
    @Test
    func decode_withoutContents_keepsTheKey() throws {
        let json = """
        {
          "item_identifier" : "vault.item.private-key.v1",
          "key" : "the key",
          "title" : "Title"
        }
        """

        let decoded = try testDecoder().decode(PrivateKey.EncryptedContainer.self, from: Data(json.utf8))

        #expect(PrivateKey(encryptedContainer: decoded) == PrivateKey(title: "Title", key: "the key", contents: ""))
    }

    @Test
    func encryptAndDecrypt_roundTripsEveryKey() throws {
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")

        for privateKey in privateKeyFixtures {
            let encrypted = try VaultItemEncryptor(key: key).encrypt(item: privateKey)
            let decrypted: PrivateKey = try VaultItemDecryptor(key: key).decrypt(
                item: encrypted,
                expectedItemIdentifier: VaultIdentifiers.Item.privateKey,
            )

            #expect(encrypted.title == privateKey.title)
            #expect(!encrypted.data.isEmpty)
            expectExactlyEqual(decrypted, privateKey)
        }
    }

    /// Opened as a recovery phrase, a private key isn't anything else by mistake.
    @Test
    func decrypt_asARecoveryPhrase_fails() throws {
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")
        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: anyPrivateKey())

        #expect(throws: (any Error).self) {
            let _: RecoveryPhrase = try VaultItemDecryptor(key: key).decrypt(
                item: encrypted,
                expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
            )
        }
    }
}

// MARK: - Helpers

extension PrivateKeyEncryptableTests {
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

/// Checks that two keys are identical down to the Unicode scalars, rather than only canonically equivalent (which is
/// what `String`'s `==` checks).
func expectExactlyEqual(
    _ actual: PrivateKey,
    _ expected: PrivateKey,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    func scalars(_ string: String) -> [UInt32] {
        string.unicodeScalars.map(\.value)
    }

    #expect(scalars(actual.title) == scalars(expected.title), sourceLocation: sourceLocation)
    #expect(scalars(actual.key) == scalars(expected.key), sourceLocation: sourceLocation)
    #expect(scalars(actual.contents) == scalars(expected.contents), sourceLocation: sourceLocation)
}
