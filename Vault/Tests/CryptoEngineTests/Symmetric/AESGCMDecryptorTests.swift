import CryptoEngine
import CryptoSwift
import Foundation
import Testing

struct AESGCMDecryptorTests {
    @Test
    func decrypt_decryptsEmptyMessageWithItsTag() throws {
        // NIST GCM test case 1: a zero key and IV, and no plaintext.
        let key = Data(hex: "00000000000000000000000000000000")
        let iv = Data(hex: "000000000000000000000000")
        let message = AESGCMEncryptedMessage(
            ciphertext: Data(),
            authenticationTag: Data(hex: "58e2fccefa7e3061367f1d57a4e7455a"),
        )

        let sut = makeSUT(key: key)
        let decrypted = try sut.decrypt(message: message, iv: iv)

        #expect(decrypted == Data())
    }

    @Test(arguments: ["58e2fccefa7e3061367f1d57a4e7455b", "00000000000000000000000000000000"])
    func decrypt_throwsErrorIfTagIsBadForEmptyMessage(tag: String) {
        let key = Data(hex: "00000000000000000000000000000000")
        let iv = Data(hex: "000000000000000000000000")
        let message = AESGCMEncryptedMessage(ciphertext: Data(), authenticationTag: Data(hex: tag))

        let sut = makeSUT(key: key)
        #expect(throws: AESGCMDecryptor.DecryptionError.authenticationFailed) {
            try sut.decrypt(message: message, iv: iv)
        }
    }

    @Test(arguments: [0, 1, 4, 8, 12, 15, 17, 32])
    func decrypt_throwsErrorIfTagIsNotFullLength(length: Int) {
        let key = Data(hex: "0xfeffe9928665731c6d6a8f9467308308")
        let iv = Data(hex: "0xcafebabefacedbaddecaf888")
        // A prefix of the right tag, padded with more of it where the tag is too long.
        let rightTag = Data(hex: "0x4d5c2af327cd64a62cf35abd2ba6fab4")
        let message = AESGCMEncryptedMessage(
            ciphertext: Data(
                hex: "0x42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985",
            ),
            authenticationTag: Data((rightTag + rightTag).prefix(length)),
        )

        let sut = makeSUT(key: key)
        #expect(throws: AESGCMDecryptor.DecryptionError.invalidAuthenticationTagLength) {
            try sut.decrypt(message: message, iv: iv)
        }
    }

    @Test(arguments: [0, 1, 15])
    func decrypt_throwsErrorIfTagIsNotFullLengthForEmptyMessage(length: Int) {
        let key = Data(hex: "00000000000000000000000000000000")
        let iv = Data(hex: "000000000000000000000000")
        let message = AESGCMEncryptedMessage(
            ciphertext: Data(),
            authenticationTag: Data(Data(hex: "58e2fccefa7e3061367f1d57a4e7455a").prefix(length)),
        )

        let sut = makeSUT(key: key)
        #expect(throws: AESGCMDecryptor.DecryptionError.invalidAuthenticationTagLength) {
            try sut.decrypt(message: message, iv: iv)
        }
    }

    @Test
    func decrypt_roundTripsAnEmptyMessageFromTheEncryptor() throws {
        let key = Data(repeating: 0x11, count: 32)
        let iv = Data(repeating: 0x22, count: 32)
        let sealed = try AESGCMEncryptor(key: key).encrypt(plaintext: Data(), iv: iv)

        let decrypted = try makeSUT(key: key).decrypt(message: sealed, iv: iv)

        #expect(sealed.authenticationTag.count == AESGCMDecryptor.authenticationTagLength)
        #expect(decrypted == Data())
    }

    @Test
    func decrypt_decryptsNonEmptyMessage() throws {
        let key = Data(hex: "0xfeffe9928665731c6d6a8f9467308308")
        let iv = Data(hex: "0xcafebabefacedbaddecaf888")
        let plaintext =
            Data(
                hex: "0xd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255",
            )
        let message = AESGCMEncryptedMessage(
            ciphertext: Data(
                hex: "0x42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985",
            ),
            authenticationTag: Data(hex: "0x4d5c2af327cd64a62cf35abd2ba6fab4"),
        )

        let sut = makeSUT(key: key)
        let decrypted = try sut.decrypt(message: message, iv: iv)

        #expect(decrypted == plaintext)
    }

    @Test
    func decrypt_throwsErrorIfTagIsBadForNonEmptyMessage() {
        let key = Data(hex: "0xfeffe9928665731c6d6a8f9467308308")
        let iv = Data(hex: "0xcafebabefacedbaddecaf888")
        let message = AESGCMEncryptedMessage(
            ciphertext: Data(
                hex: "0x42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985",
            ),
            authenticationTag: Data(hex: "0x4d5c2af327cd64a62cf35abd2ba6fab5"), // tag is slightly off
        )

        let sut = makeSUT(key: key)
        #expect(throws: (any Error).self, performing: {
            try sut.decrypt(message: message, iv: iv)
        })
    }
}

// MARK: - Helpers

extension AESGCMDecryptorTests {
    private func makeSUT(key: Data = anyData()) -> AESGCMDecryptor {
        AESGCMDecryptor(key: key)
    }
}
