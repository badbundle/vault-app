import CryptoEngine
import Foundation
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed

struct VaultItemReencryptorTests {
    @Test
    func reencrypt_holdsExactlyWhatTheItemHeldUnderTheNewKey() throws {
        let note = SecureNote(title: "Safe combination", contents: "12-34-56", format: .markdown)
        let oldKey = try VaultKeyDeriver.Item.Fast.v1.createEncryptionKey(password: "open sesame")
        let item = try VaultItemEncryptor(key: oldKey).encrypt(item: note)
        let newKey = try VaultKeyDeriver.Item.Fast.v2.createEncryptionKey(password: "open sesame")

        let reencrypted = try VaultItemReencryptor().reencrypt(item, from: oldKey, to: newKey)

        let decryptor = AESGCMDecryptor(key: newKey.key.data)
        let plaintext = try decryptor.decrypt(
            message: .init(ciphertext: reencrypted.data, authenticationTag: reencrypted.authentication),
            iv: reencrypted.encryptionIV,
        )
        let original = try AESGCMDecryptor(key: oldKey.key.data).decrypt(
            message: .init(ciphertext: item.data, authenticationTag: item.authentication),
            iv: item.encryptionIV,
        )
        #expect(plaintext == original)
        let decrypted: SecureNote = try VaultItemDecryptor(key: newKey)
            .decrypt(item: reencrypted, expectedItemIdentifier: VaultIdentifiers.Item.secureNote)
        #expect(decrypted == note)
    }

    @Test
    func reencrypt_changesOnlyTheKeyAndTheEncryption() throws {
        let oldKey = try VaultKeyDeriver.Item.Fast.v1.createEncryptionKey(password: "open sesame")
        let item = try VaultItemEncryptor(key: oldKey).encrypt(item: anyRecoveryPhrase(title: "Wallet"))
        let newKey = try VaultKeyDeriver.Item.Fast.v2.createEncryptionKey(password: "open sesame")

        let reencrypted = try VaultItemReencryptor().reencrypt(item, from: oldKey, to: newKey)

        #expect(reencrypted.version == item.version)
        #expect(reencrypted.title == item.title)
        #expect(reencrypted.keygenSalt == newKey.salt)
        #expect(reencrypted.keygenSignature == VaultKeyDeriver.Signature.itemFastV2.rawValue)
        #expect(reencrypted.encryptionIV != item.encryptionIV)
        #expect(reencrypted.data != item.data)
        #expect(VaultItemDecryptor(key: oldKey).canDecrypt(reencrypted) == false)
    }

    @Test
    func reencrypt_withAKeyThatDoesntOpenIt_throws() throws {
        let oldKey = try VaultKeyDeriver.Item.Fast.v1.createEncryptionKey(password: "open sesame")
        let item = try VaultItemEncryptor(key: oldKey).encrypt(item: anySecureNote())
        let wrongKey = try VaultKeyDeriver.Item.Fast.v1.createEncryptionKey(password: "wrong")
        let newKey = try VaultKeyDeriver.Item.Fast.v2.createEncryptionKey(password: "open sesame")

        #expect(throws: (any Error).self) {
            try VaultItemReencryptor().reencrypt(item, from: wrongKey, to: newKey)
        }
    }
}

extension VaultItemDecryptor {
    fileprivate func canDecrypt(_ item: EncryptedItem) -> Bool {
        (try? decryptItemIdentifier(item: item)) != nil
    }
}
