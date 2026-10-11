import CryptoEngine
import Foundation
import FoundationExtensions
import Testing
import VaultKeygen

/// Pins the exact KDF chain — algorithm order, key length, iteration
/// counts, variants, and cost factors — for every production deriver.
///
/// `uniqueAlgorithmIdentifier` encodes all parameters (including nesting
/// via `COMBINATION<...|...>`), so any drift in the chains fails here on
/// every run. This exists because a full pinned-vector test of
/// `Backup.Secure.v1` costs half a minute of scrypt per debug run and would
/// rot skipped; the fast pinned vectors in `VaultKeyDeriverTests` prove the
/// shared composition machinery, `PBKDF2KeyDeriverTests` pins its PBKDF2
/// step's output, and this test pins the secure parameters. The v2
/// derivations, which are Argon2id, also derive known answers with their
/// real parameters (`VaultKeyDeriverRealParameterTests`, below).
struct VaultKeyDeriverParameterPinTests {
    @Test
    func backupSecureV1_pinsExactKDFChain() {
        // The deriver that protects stolen backups. Changing any of these
        // parameters is a new keygen VERSION (a new signature), never an
        // edit to v1 — existing backups derive with these exact values.
        #expect(VaultKeyDeriver.Backup.Secure.v1
            .uniqueAlgorithmIdentifier ==
            "COMBINATION<PBKDF2<keyLength=32;iterations=5452351;variant=sha384>|HKDF<keyLength=32;variant=sha3_sha512>|SCRYPT<keyLength=32;costFactor=262144;blockSizeFactor=8;parallelizationFactor=1>>")
    }

    @Test
    func backupFastV1_pinsExactKDFChain() {
        #expect(VaultKeyDeriver.Backup.Fast.v1
            .uniqueAlgorithmIdentifier ==
            "COMBINATION<PBKDF2<keyLength=32;iterations=2000;variant=sha384>|HKDF<keyLength=32;variant=sha3_sha512>|SCRYPT<keyLength=32;costFactor=64;blockSizeFactor=4;parallelizationFactor=1>>")
    }

    @Test
    func itemSecureV1_pinsExactKDFChain() {
        #expect(VaultKeyDeriver.Item.Secure.v1
            .uniqueAlgorithmIdentifier ==
            "COMBINATION<SCRYPT<keyLength=32;costFactor=256;blockSizeFactor=4;parallelizationFactor=1>|PBKDF2<keyLength=32;iterations=372002;variant=sha384>>")
    }

    @Test
    func itemFastV1_pinsExactKDFChain() {
        #expect(VaultKeyDeriver.Item.Fast.v1
            .uniqueAlgorithmIdentifier ==
            "COMBINATION<SCRYPT<keyLength=32;costFactor=64;blockSizeFactor=4;parallelizationFactor=1>|PBKDF2<keyLength=32;iterations=1001;variant=sha384>>")
    }

    @Test
    func backupSecureV2_pinsExactKDFChain() {
        #expect(VaultKeyDeriver.Backup.Secure.v2
            .uniqueAlgorithmIdentifier ==
            "ARGON2ID<keyLength=32;memoryKiB=524288;iterations=32;parallelism=4;version=19>")
    }

    @Test
    func backupSecureV1ThenV2_pinsExactKDFChain() {
        // Backups made with a stored v1 key carried on to v2 restore with exactly this: v1 from the password, then
        // v2's Argon2id with the salt behind the signature's ID.
        #expect(VaultKeyDeriver.Backup.Secure.v1ThenV2
            .uniqueAlgorithmIdentifier ==
            "COMBINATION<COMBINATION<PBKDF2<keyLength=32;iterations=5452351;variant=sha384>|HKDF<keyLength=32;variant=sha3_sha512>|SCRYPT<keyLength=32;costFactor=262144;blockSizeFactor=8;parallelizationFactor=1>>|LABELLED_SALT<label=vault.keygen.backup.secure.v1-then-v2;ARGON2ID<keyLength=32;memoryKiB=524288;iterations=32;parallelism=4;version=19>>>")
    }

    @Test
    func backupFastV2_pinsExactKDFChain() {
        #expect(VaultKeyDeriver.Backup.Fast.v2
            .uniqueAlgorithmIdentifier ==
            "ARGON2ID<keyLength=32;memoryKiB=8192;iterations=2;parallelism=4;version=19>")
    }

    @Test
    func backupFastV1ThenV2_pinsExactKDFChain() {
        #expect(VaultKeyDeriver.Backup.Fast.v1ThenV2
            .uniqueAlgorithmIdentifier ==
            "COMBINATION<COMBINATION<PBKDF2<keyLength=32;iterations=2000;variant=sha384>|HKDF<keyLength=32;variant=sha3_sha512>|SCRYPT<keyLength=32;costFactor=64;blockSizeFactor=4;parallelizationFactor=1>>|LABELLED_SALT<label=vault.keygen.backup.fast.v1-then-v2;ARGON2ID<keyLength=32;memoryKiB=8192;iterations=2;parallelism=4;version=19>>>")
    }

    @Test
    func itemSecureV2_pinsExactKDFChain() {
        #expect(VaultKeyDeriver.Item.Secure.v2
            .uniqueAlgorithmIdentifier ==
            "ARGON2ID<keyLength=32;memoryKiB=262144;iterations=4;parallelism=4;version=19>")
    }

    @Test
    func itemFastV2_pinsExactKDFChain() {
        #expect(VaultKeyDeriver.Item.Fast.v2
            .uniqueAlgorithmIdentifier ==
            "ARGON2ID<keyLength=32;memoryKiB=4096;iterations=2;parallelism=4;version=19>")
    }

    @Test
    func signatureIDs_areStable() {
        // These raw values are persisted in backups and the keychain to
        // look up the deriver at decrypt time — they can never change.
        #expect(VaultKeyDeriver.Signature.backupSecureV1.rawValue == "vault.keygen.backup.secure.v1")
        #expect(VaultKeyDeriver.Signature.backupFastV1.rawValue == "vault.keygen.backup.fast.v1")
        #expect(VaultKeyDeriver.Signature.itemSecureV1.rawValue == "vault.keygen.item.secure.v1")
        #expect(VaultKeyDeriver.Signature.itemFastV1.rawValue == "vault.keygen.item.fast.v1")
        #expect(VaultKeyDeriver.Signature.backupSecureV2.rawValue == "vault.keygen.backup.secure.v2")
        #expect(VaultKeyDeriver.Signature.backupFastV2.rawValue == "vault.keygen.backup.fast.v2")
        #expect(VaultKeyDeriver.Signature.backupSecureV1ThenV2.rawValue == "vault.keygen.backup.secure.v1-then-v2")
        #expect(VaultKeyDeriver.Signature.backupFastV1ThenV2.rawValue == "vault.keygen.backup.fast.v1-then-v2")
        #expect(VaultKeyDeriver.Signature.itemSecureV2.rawValue == "vault.keygen.item.secure.v2")
        #expect(VaultKeyDeriver.Signature.itemFastV2.rawValue == "vault.keygen.item.fast.v2")
        #expect(VaultKeyDeriver.Signature.testing.rawValue == "vault.keygen.testing")
        #expect(VaultKeyDeriver.Signature.failing.rawValue == "vault.keygen.failing")
    }

    @Test
    func upgrades_moveEachV1DerivationToItsV2() {
        // What an item or a stored backup key moves to the next time the app opens or loads it. Every other
        // signature stays as it is.
        let itemUpgrades = Dictionary(uniqueKeysWithValues: VaultKeyDeriver.Signature.allCases.compactMap { signature in
            signature.itemUpgrade.map { (signature, $0) }
        })
        #expect(itemUpgrades == [.itemSecureV1: .itemSecureV2, .itemFastV1: .itemFastV2])
        let backupKeyUpgrades = Dictionary(uniqueKeysWithValues: VaultKeyDeriver.Signature.allCases.compactMap {
            signature in signature.storedBackupKeyUpgrade.map { (signature, $0) }
        })
        #expect(backupKeyUpgrades == [
            .backupSecureV1: .backupSecureV1ThenV2,
            .backupFastV1: .backupFastV1ThenV2,
        ])
    }

    @Test
    func lookup_returnsDeriverMatchingEverySignature() {
        for signature in VaultKeyDeriver.Signature.allCases {
            let deriver = VaultKeyDeriver.lookup(signature: signature)
            #expect(deriver.signature == signature)
        }
    }
}

/// The secure v2 derivations with the parameters they ship with, against known answers from another build of the
/// Argon2 reference (argon2-cffi 25.1.0). They take seconds and hundreds of MiB each, so these are the only tests
/// that run them, one at a time: every other test uses the fast derivations or `testing`.
@Suite(.serialized)
struct VaultKeyDeriverRealParameterTests {
    @Test(.timeLimit(.minutes(2)))
    func itemSecureV2_derivesTheKnownAnswer() throws {
        let key = try VaultKeyDeriver.Item.Secure.v2.recreateEncryptionKey(
            password: "hello world",
            salt: Data("somesalt".utf8),
        )

        #expect(key.key.data.toHexString() == "d7c60e09632c0cbd13d44a4433f2298254f83f499a0b1efd3c577964f72b9b61")
    }

    @Test(.timeLimit(.minutes(5)))
    func backupSecureV1ThenV2_carryingOnAStoredKey_derivesTheKnownAnswer() throws {
        // How the app moves a stored v1 key on, and the second half of every restore of a backup made with one.
        let storedKey = try DerivedEncryptionKey(
            key: KeyData(data: Data(0 ..< 32)),
            salt: Data("somesalt".utf8),
            keyDervier: .backupSecureV1,
        )

        let key = try VaultKeyDeriver.Backup.Secure.v1ThenV2.continueDerivation(from: storedKey)

        #expect(key.key.data.toHexString() == "b8834f344aed0d26fd2c8109092005b27d587a13db6f0b52c3244042b3d1c49a")
        #expect(key.salt == storedKey.salt)
        #expect(key.keyDervier == .backupSecureV1ThenV2)
    }
}
