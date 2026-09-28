import Foundation
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed

struct DerivedEncryptionKeyTests {
    @Test
    func newVaultKeyWithRandomIV_usesSameKeyEachTime() throws {
        let key = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)

        var seenKeys = Set<KeyData<32>>()
        for _ in 0 ..< 10 {
            let newKey = try key.newVaultKeyWithRandomIV()
            seenKeys.insert(newKey.key)
        }

        #expect(seenKeys.count == 1)
    }

    @Test
    func newVaultKeyWithRandomIV_usesRandomIVEachTime() throws {
        let key = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)

        var seenIVs = Set<KeyData<32>>()
        for _ in 0 ..< 10 {
            let newKey = try key.newVaultKeyWithRandomIV()
            seenIVs.insert(newKey.iv)
        }

        #expect(seenIVs.count == 10)
    }

    @Test
    func description_leavesOutTheKey() throws {
        let sut = try DerivedEncryptionKey(
            key: KeyData<32>(data: Data(repeating: 0xAB, count: 32)),
            salt: Data(repeating: 0xCD, count: 16),
            keyDervier: .backupFastV1,
        )

        let representations = [
            String(describing: sut),
            String(reflecting: sut),
            "\(sut)",
            String(describing: [sut]),
            String(describing: Optional(sut) as Any),
            dumped(sut),
        ]
        for representation in representations {
            #expect(!representation.lowercased().contains("abab"))
            #expect(!representation.contains("171"), "The key's bytes, in decimal")
            #expect(!representation.lowercased().contains("cdcd"))
            #expect(representation.contains("vault.keygen.backup.fast.v1"))
        }
    }

    @Test
    func mirror_showsOnlyTheKeyDeriver() {
        let sut = DerivedEncryptionKey(key: .random(), salt: .random(count: 16), keyDervier: .testing)

        let children = Mirror(reflecting: sut).children.map { "\($0.label ?? ""): \($0.value)" }

        #expect(children == ["keyDeriver: vault.keygen.testing"])
    }

    private func dumped(_ value: some Any) -> String {
        var output = ""
        dump(value, to: &output)
        return output
    }
}
