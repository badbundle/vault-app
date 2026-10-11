import CryptoEngine
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import VaultKeygen

/// Key derivation may be very slow, so most tests verify the identifier.
/// Targeted fast vector tests run real derivation where we need end-to-end coverage.
///
/// Each respective version of each algorithm should never change, so it's always backwards compatible.
struct VaultKeyDeriverTests {
    @Test
    func Backup_Fast_v1() {
        let fast = VaultKeyDeriver.Backup.Fast.v1

        #expect(fast.signature == .backupFastV1)
        #expect(fast.signature.userVisibleDescription == "Vault Backup (Fast, v1)")
        #expect(fast.uniqueAlgorithmIdentifier == """
        COMBINATION<\
        PBKDF2<keyLength=32;iterations=2000;variant=sha384>|\
        HKDF<keyLength=32;variant=sha3_sha512>|\
        SCRYPT<keyLength=32;costFactor=64;blockSizeFactor=4;parallelizationFactor=1>\
        >
        """)
    }

    @Test
    func Backup_Secure_v1() {
        let secure = VaultKeyDeriver.Backup.Secure.v1

        #expect(secure.signature == .backupSecureV1)
        #expect(secure.signature.userVisibleDescription == "Vault Backup (Secure, v1)")
        #expect(secure.uniqueAlgorithmIdentifier == """
        COMBINATION<\
        PBKDF2<keyLength=32;iterations=5452351;variant=sha384>|\
        HKDF<keyLength=32;variant=sha3_sha512>|\
        SCRYPT<keyLength=32;costFactor=262144;blockSizeFactor=8;parallelizationFactor=1>\
        >
        """)
    }

    @Test
    func Backup_Fast_v1_recreatesExpectedKeyForSamePasswordAndSalt() throws {
        let result = try VaultKeyDeriver.Backup.Fast.v1.recreateEncryptionKey(
            password: "hello world",
            salt: Data("salt".utf8),
        )

        #expect(result.key.data.toHexString() == """
        b3adfcb644c0d7a4086e2a8a1c784eb5aa422a1b40dc4e4f088d1b7a40025e0f
        """)
        #expect(result.salt == Data("salt".utf8))
        #expect(result.keyDervier == .backupFastV1)
    }

    @Test
    func Item_Fast_v1() {
        let fast = VaultKeyDeriver.Item.Fast.v1

        #expect(fast.signature == .itemFastV1)
        #expect(fast.signature.userVisibleDescription == "Vault Item (Fast, v1)")
        #expect(fast.uniqueAlgorithmIdentifier == """
        COMBINATION<\
        SCRYPT<keyLength=32;costFactor=64;blockSizeFactor=4;parallelizationFactor=1>|\
        PBKDF2<keyLength=32;iterations=1001;variant=sha384>\
        >
        """)
    }

    @Test
    func Item_Fast_v1_recreatesExpectedKeyForSamePasswordAndSalt() throws {
        let result = try VaultKeyDeriver.Item.Fast.v1.recreateEncryptionKey(
            password: "hello world",
            salt: Data("salt".utf8),
        )

        #expect(result.key.data.toHexString() == """
        a2f84c8bfccfb4794b70adb71bd5ab7f9cd311cb59fdcbcdd8ec7e46b36eb449
        """)
        #expect(result.salt == Data("salt".utf8))
        #expect(result.keyDervier == .itemFastV1)
    }

    @Test
    func Item_Secure_v1() {
        let secure = VaultKeyDeriver.Item.Secure.v1

        #expect(secure.signature == .itemSecureV1)
        #expect(secure.signature.userVisibleDescription == "Vault Item (Secure, v1)")
        #expect(secure.uniqueAlgorithmIdentifier == """
        COMBINATION<\
        SCRYPT<keyLength=32;costFactor=256;blockSizeFactor=4;parallelizationFactor=1>|\
        PBKDF2<keyLength=32;iterations=372002;variant=sha384>\
        >
        """)
    }

    /// Derived before VAULT-128, when PBKDF2 was CryptoSwift's. Items encrypted with their own password use this.
    @Test
    func Item_Secure_v1_recreatesExpectedKeyForSamePasswordAndSalt() throws {
        let result = try VaultKeyDeriver.Item.Secure.v1.recreateEncryptionKey(
            password: "hello world",
            salt: Data("salt".utf8),
        )

        #expect(result.key.data.toHexString() == """
        b90904e2241fe404a7b6a0a483db830dd6534e79a59b4c63e62f24f0e689d268
        """)
        #expect(result.salt == Data("salt".utf8))
        #expect(result.keyDervier == .itemSecureV1)
    }

    @Test
    func Backup_Fast_v2() {
        let fast = VaultKeyDeriver.Backup.Fast.v2

        #expect(fast.signature == .backupFastV2)
        #expect(fast.signature.userVisibleDescription == "Vault Backup (Fast, v2)")
        #expect(fast.uniqueAlgorithmIdentifier == """
        ARGON2ID<keyLength=32;memoryKiB=8192;iterations=2;parallelism=4;version=19>
        """)
    }

    @Test
    func Backup_Secure_v2() {
        let secure = VaultKeyDeriver.Backup.Secure.v2

        #expect(secure.signature == .backupSecureV2)
        #expect(secure.signature.userVisibleDescription == "Vault Backup (Secure, v2)")
        #expect(secure.uniqueAlgorithmIdentifier == """
        ARGON2ID<keyLength=32;memoryKiB=524288;iterations=32;parallelism=4;version=19>
        """)
    }

    @Test
    func Backup_v1ThenV2_descriptions() {
        #expect(VaultKeyDeriver.Backup.Fast.v1ThenV2.signature == .backupFastV1ThenV2)
        #expect(VaultKeyDeriver.Backup.Secure.v1ThenV2.signature == .backupSecureV1ThenV2)
        #expect(VaultKeyDeriver.Signature.backupFastV1ThenV2
            .userVisibleDescription == "Vault Backup (Fast, v1 then v2)")
        #expect(
            VaultKeyDeriver.Signature.backupSecureV1ThenV2.userVisibleDescription ==
                "Vault Backup (Secure, v1 then v2)",
        )
    }

    @Test
    func Item_v2_descriptions() {
        #expect(VaultKeyDeriver.Item.Fast.v2.signature == .itemFastV2)
        #expect(VaultKeyDeriver.Item.Secure.v2.signature == .itemSecureV2)
        #expect(VaultKeyDeriver.Signature.itemFastV2.userVisibleDescription == "Vault Item (Fast, v2)")
        #expect(VaultKeyDeriver.Signature.itemSecureV2.userVisibleDescription == "Vault Item (Secure, v2)")
    }

    // Known answers from another build of the Argon2 reference (argon2-cffi 25.1.0), and for v1 from Python's
    // PBKDF2 and the cryptography package's HKDF and scrypt, which match the v1 vectors above.

    @Test
    func Backup_Fast_v2_recreatesExpectedKeyForSamePasswordAndSalt() throws {
        let result = try VaultKeyDeriver.Backup.Fast.v2.recreateEncryptionKey(
            password: "hello world",
            salt: Data("somesalt".utf8),
        )

        #expect(result.key.data.toHexString() == """
        d5c027e2ea1b3a747415985fa8b4a5b43c7292f03d1050f615ace99469e0d82b
        """)
        #expect(result.keyDervier == .backupFastV2)
    }

    @Test
    func Item_Fast_v2_recreatesExpectedKeyForSamePasswordAndSalt() throws {
        let result = try VaultKeyDeriver.Item.Fast.v2.recreateEncryptionKey(
            password: "hello world",
            salt: Data("somesalt".utf8),
        )

        #expect(result.key.data.toHexString() == """
        0973cee10290701b1cfb8c8a939c93aaf36d386d04e43d94463576d6524c3c93
        """)
        #expect(result.keyDervier == .itemFastV2)
    }

    @Test
    func Backup_Fast_v1ThenV2_recreatesExpectedKeyForSamePasswordAndSalt() throws {
        // v1 from the password, then v2's Argon2id over v1's key, with the salt behind the signature's ID.
        let result = try VaultKeyDeriver.Backup.Fast.v1ThenV2.recreateEncryptionKey(
            password: "hello world",
            salt: Data("somesalt".utf8),
        )

        #expect(result.key.data.toHexString() == """
        4841b68dca52e560665455a81757aef3af4f62dda2c59d9d92082f2959385ac9
        """)
        #expect(result.salt == Data("somesalt".utf8))
        #expect(result.keyDervier == .backupFastV1ThenV2)
    }

    @Test
    func continueDerivation_fromAStoredV1Key_isTheKeyThePasswordRecreates() throws {
        let salt = Data("somesalt".utf8)
        let stored = try VaultKeyDeriver.Backup.Fast.v1.recreateEncryptionKey(password: "hello world", salt: salt)
        #expect(stored.key.data.toHexString() == """
        38a40574c9816c6b68933b06bc7f2e56436300ffc4d8297ac3e57d6e143e6333
        """)

        let continued = try VaultKeyDeriver.Backup.Fast.v1ThenV2.continueDerivation(from: stored)

        let recreated = try VaultKeyDeriver.Backup.Fast.v1ThenV2.recreateEncryptionKey(
            password: "hello world",
            salt: salt,
        )
        #expect(continued == recreated)
        #expect(continued.salt == salt)
        #expect(continued.keyDervier == .backupFastV1ThenV2)
    }

    @Test
    func continueDerivation_fromAKeyOfAnotherDerivation_throws() throws {
        let stored = try VaultKeyDeriver.Backup.Fast.v2.createEncryptionKey(password: "hello world")

        #expect(throws: VaultKeyDeriver.NotAContinuationError.self) {
            try VaultKeyDeriver.Backup.Fast.v1ThenV2.continueDerivation(from: stored)
        }
        #expect(throws: VaultKeyDeriver.NotAContinuationError.self) {
            try VaultKeyDeriver.Backup.Secure.v1ThenV2.continueDerivation(from: stored)
        }
    }

    @Test
    func continueDerivation_withADerivationThatCarriesNothingOn_throws() throws {
        let stored = try VaultKeyDeriver.Backup.Fast.v1.createEncryptionKey(password: "hello world")

        for deriver in [VaultKeyDeriver.Backup.Fast.v2, .Backup.Fast.v1, .testing] {
            #expect(throws: VaultKeyDeriver.NotAContinuationError.self) {
                try deriver.continueDerivation(from: stored)
            }
        }
    }

    @Test
    func tryFromString_aSignatureThisVersionDoesntKnow_saysToUpdateVault() {
        let error = #expect(throws: VaultKeyDeriver.MissingKeyDeriverError.self) {
            try VaultKeyDeriver.Signature(tryFromString: "vault.keygen.backup.secure.v3")
        }

        #expect(error?.errorDescription == "Needs a Newer Version of Vault")
        #expect(error?.failureReason == "This was made by a newer version of Vault. Update Vault, then try again.")
    }

    @Test(arguments: VaultKeyDeriver.Signature.allCases)
    func lookupSignature_looksUpCorrect(signature: VaultKeyDeriver.Signature) {
        let result = VaultKeyDeriver.lookup(signature: signature)
        #expect(result.signature == signature)
    }

    @Test
    func createEncryptionKey_usesRandomSalt() throws {
        let sut = VaultKeyDeriver.testing

        var seenKeys = Set<KeyData<32>>()
        var seenSalt = Set<Data>()
        var seenKeyDeriver = Set<VaultKeyDeriver.Signature>()
        for _ in 0 ..< 100 {
            let key = try sut.createEncryptionKey(password: "password")
            seenKeys.insert(key.key)
            seenSalt.insert(key.salt)
            seenKeyDeriver.insert(key.keyDervier)
        }

        #expect(seenKeys.count == 100)
        #expect(seenSalt.count == 100)
        #expect(seenKeyDeriver.count == 1)
        #expect(seenKeyDeriver.first == .testing)
    }

    @Test
    func recreateEncryptionKey_usesTheSameSalt() throws {
        let salt = Data(hex: "aabbccddeeff")
        let sut = VaultKeyDeriver.testing

        var seenKeys = Set<KeyData<32>>()
        var seenSalt = Set<Data>()
        var seenKeyDeriver = Set<VaultKeyDeriver.Signature>()

        for _ in 0 ..< 100 {
            let key = try sut.recreateEncryptionKey(password: "password", salt: salt)
            seenKeys.insert(key.key)
            seenSalt.insert(key.salt)
            seenKeyDeriver.insert(key.keyDervier)
        }

        #expect(seenKeys.count == 1)
        #expect(seenSalt.count == 1)
        #expect(seenKeyDeriver.count == 1)
        #expect(
            seenKeys.first?.data.toHexString() ==
                "b8ab51d4c385654810dbcc8e860426143a7b61a4273805ba9596b1f9c00530c6",
        )
        #expect(seenSalt.first?.toHexString() == "aabbccddeeff")
        #expect(seenKeyDeriver.first == .testing)
    }
}
