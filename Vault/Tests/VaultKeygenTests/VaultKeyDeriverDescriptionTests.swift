import Foundation
import Testing
import VaultKeygen

struct VaultKeyDeriverDescriptionTests {
    @Test(arguments: [
        (VaultKeyDeriver.Signature.backupSecureV2, "Argon2id, 512 MiB, 32 passes, 4 lanes"),
        (.backupSecureV1, "PBKDF2, HKDF and scrypt"),
        (.backupSecureV1ThenV2, "PBKDF2, HKDF and scrypt, then Argon2id, 512 MiB, 32 passes, 4 lanes"),
        (.backupFastV2, "Argon2id, 8 MiB, 2 passes, 4 lanes"),
        (.itemSecureV1, "scrypt and PBKDF2"),
    ])
    func derivationDescription_saysHowTheKeyIsMade(signature: VaultKeyDeriver.Signature, expected: String) {
        #expect(signature.derivationDescription == expected)
    }

    /// Argon2id's numbers come from the parameters it runs with.
    @Test
    func derivationDescription_followsTheParameters() {
        let parameters = VaultKeyDeriver.Item.Secure.v2Parameters

        #expect(
            VaultKeyDeriver.Signature.itemSecureV2.derivationDescription
                ==
                "Argon2id, \(parameters.memoryKiB / 1024) MiB, \(parameters.iterations) passes, \(parameters.parallelism) lanes",
        )
    }

    @Test(arguments: [VaultKeyDeriver.Signature.testing, .failing])
    func derivationDescription_testDerivations_haveNone(signature: VaultKeyDeriver.Signature) {
        #expect(signature.derivationDescription == nil)
    }
}
