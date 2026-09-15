import Foundation
import Testing
import VaultKeygen

/// Pins the exact KDF chain — algorithm order, key length, iteration
/// counts, variants, and cost factors — for every production deriver.
///
/// `uniqueAlgorithmIdentifier` encodes all parameters (including nesting
/// via `COMBINATION<...|...>`), so any drift in the chains fails here on
/// every run. This exists because a full pinned-vector test of
/// `Backup.Secure.v1` costs minutes of KDF per run and would rot skipped;
/// the fast pinned vectors in `VaultKeyDeriverTests` prove the shared
/// composition machinery, and this test pins the secure parameters.
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
    func signatureIDs_areStable() {
        // These raw values are persisted in backups and the keychain to
        // look up the deriver at decrypt time — they can never change.
        #expect(VaultKeyDeriver.Signature.backupSecureV1.rawValue == "vault.keygen.backup.secure.v1")
        #expect(VaultKeyDeriver.Signature.backupFastV1.rawValue == "vault.keygen.backup.fast.v1")
        #expect(VaultKeyDeriver.Signature.itemSecureV1.rawValue == "vault.keygen.item.secure.v1")
        #expect(VaultKeyDeriver.Signature.itemFastV1.rawValue == "vault.keygen.item.fast.v1")
        #expect(VaultKeyDeriver.Signature.testing.rawValue == "vault.keygen.testing")
        #expect(VaultKeyDeriver.Signature.failing.rawValue == "vault.keygen.failing")
    }

    @Test
    func lookup_returnsDeriverMatchingEverySignature() {
        for signature in VaultKeyDeriver.Signature.allCases {
            let deriver = VaultKeyDeriver.lookup(signature: signature)
            #expect(deriver.signature == signature)
        }
    }
}
