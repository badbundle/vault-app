import CoreGraphics
import Foundation
import Testing
@testable import VaultBackup

struct BackupSealTests {
    /// Seals are printed on paper that has to keep matching what Vault shows, so how a seal is worked out never
    /// changes. These values were worked out separately, with Python's `hashlib`, from the format in `BackupSeal`.
    @Test
    func digestAndCode_areFixedForever() {
        let sut = BackupSeal(encryptedVault: Self.fixedVault())

        #expect(Data(sut.digest).hexString == "cd23d4bdf826e791f30d974add997bf350a17cd03c141ccbca24e342447ba696")
        #expect(sut.code == "SMHX-9FFR")
    }

    @Test
    func code_ofAnEmptyBackupIsFixedToo() {
        let sut = BackupSeal(encryptedVault: EncryptedVault(
            version: "1.0.0",
            data: Data(),
            authentication: Data(),
            encryptionIV: Data(),
            keygenSalt: Data(),
            keygenSignature: "my-signature",
        ))

        #expect(sut.code == "C7NN-T8YG")
    }

    @Test
    func init_sameBackup_sameSeal() {
        #expect(BackupSeal(encryptedVault: Self.fixedVault()) == BackupSeal(encryptedVault: Self.fixedVault()))
    }

    /// Any change to the stored backup gives another seal, so a different backup, or a damaged copy, doesn't match.
    @Test(arguments: Field.allCases)
    func init_anyFieldChanged_anotherSeal(field: Field) {
        var changed = Self.fixedVault()
        field.change(&changed)

        #expect(BackupSeal(encryptedVault: changed) != BackupSeal(encryptedVault: Self.fixedVault()))
    }

    /// Each field is length-prefixed, so moving bytes from the end of one field to the start of the next changes it.
    @Test
    func init_bytesMovedBetweenFields_anotherSeal() {
        var moved = Self.fixedVault()
        moved.authentication.append(moved.encryptionIV.removeFirst())

        #expect(BackupSeal(encryptedVault: moved) != BackupSeal(encryptedVault: Self.fixedVault()))
    }

    @Test
    func code_isTwoGroupsOfFourInCrockfordsBase32() throws {
        let allowed = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        for byte in UInt8.min ... UInt8.max {
            let code = BackupSeal(digest: Array(repeating: byte, count: 32)).code
            let groups = code.split(separator: "-")
            try #require(groups.count == 2)
            #expect(groups.allSatisfy { $0.count == 4 && $0.allSatisfy(allowed.contains) })
        }
    }

    @Test
    func spokenCode_isOneCharacterAtATimeWithAPauseAtTheDash() {
        let sut = BackupSeal(encryptedVault: Self.fixedVault())

        #expect(sut.spokenCode == "S M H X, 9 F F R")
    }

    @Test
    func artwork_drawsTheSameEveryTime() throws {
        let seal = BackupSeal(encryptedVault: Self.fixedVault())

        let first = try Self.render(seal)
        let second = try Self.render(seal)

        #expect(first == second)
    }

    @Test
    func artwork_differentSeals_drawDifferently() throws {
        var other = Self.fixedVault()
        other.data[0] ^= 1

        let first = try Self.render(BackupSeal(encryptedVault: Self.fixedVault()))
        let second = try Self.render(BackupSeal(encryptedVault: other))

        #expect(first != second)
    }
}

extension BackupSealTests {
    enum Field: CaseIterable, Sendable {
        case version, data, authentication, encryptionIV, keygenSalt, keygenSignature

        func change(_ vault: inout EncryptedVault) {
            switch self {
            case .version: vault.version = "1.0.1"
            case .data: vault.data[0] ^= 1
            case .authentication: vault.authentication[0] ^= 1
            case .encryptionIV: vault.encryptionIV[0] ^= 1
            case .keygenSalt: vault.keygenSalt[0] ^= 1
            case .keygenSignature: vault.keygenSignature = "vault.keygen.backup.secure.v1"
            }
        }
    }

    private static func fixedVault() -> EncryptedVault {
        EncryptedVault(
            version: "1.0.0",
            data: Data(0 ..< 64),
            authentication: Data(repeating: 0x11, count: 16),
            encryptionIV: Data(repeating: 0x22, count: 12),
            keygenSalt: Data(repeating: 0x33, count: 32),
            keygenSignature: "vault.keygen.backup.secure.v2",
        )
    }

    private struct RenderFailed: Error {}

    /// The seal's pixels, drawn 100 points across into a bitmap with a y axis that points down.
    private static func render(_ seal: BackupSeal) throws -> Data {
        let size = 100
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { throw RenderFailed() }
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        BackupSealArtwork(seal: seal).draw(in: context, rect: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { throw RenderFailed() }
        return Data(bytes: data, count: size * size * 4)
    }
}

extension Data {
    fileprivate var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
