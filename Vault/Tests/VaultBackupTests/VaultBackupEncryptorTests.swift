import CryptoEngine
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultBackup

struct VaultBackupEncryptorTests {
    @Test
    func encryptBackupPayload_encryptedVaultDataIsExpectedVault() throws {
        let key = VaultKey(key: .repeating(byte: 0xAA), iv: .repeating(byte: 0xAB))
        let sut = makeSUT(key: key)

        let encryptedVault = try sut.encryptBackupPayload(items: [], tags: [], userDescription: "hello world")

        // This is the encoded payload created by this test case, which is compressed using lzma:
//        {
//          "created" : 1234000,
//          "items" : [
//
//          ],
//          "obfuscation_padding" : "",
//          "tags" : [
//
//          ],
//          "user_description" : "hello world",
//          "version" : "1.0.0"
//        }

        #expect(encryptedVault.data.toHexString() == """
        866de95d08a6b24751cdc4e9ab793585614c2062ba690a77762735d1abc866835ad0b54d1e3f29e9ffc4ad1d26a55e3a198ca9f685225042d331df50d64ad495f2a75c30000c6929c6e38a1bbfa16f0d3b81581c0d8f18ffc1df7ec773cfaa16068eb9b00c2de1268a459b3a6ae081dcdf81fe06d80ee23c8c44cb8ae6c61f519ffd7b1ce50efdbcd35e2a1e1eebd0571c924e0ad55f3f85a07b203005aea9e1314e85d36d065de2
        """)
        #expect(encryptedVault.authentication.toHexString() == """
        f5228102f094dbc0703270d39bac6b81
        """)
        #expect(encryptedVault.encryptionIV.toHexString() == """
        abababababababababababababababababababababababababababababababab
        """)
    }

    @Test
    func encryptBackupPayload_encryptedVaultDataIsExpectedVaultWithFixedPadding() throws {
        let key = VaultKey(key: .repeating(byte: 0xAA), iv: .repeating(byte: 0xAB))
        let padding = VaultBackupEncryptor.PaddingMode.fixed(data: Data(repeating: 0xF1, count: 45))
        let sut = makeSUT(key: key, paddingMode: padding)

        let encryptedVault = try sut.encryptBackupPayload(items: [], tags: [], userDescription: "hello world")

        // This is the encoded payload created by this test case:

//        {
//          "created" : 1234000,
//          "items" : [
//
//          ],
//          "obfuscation_padding" : "8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx",
//          "tags" : [
//
//          ],
//          "user_description" : "hello world",
//          "version" : "1.0.0"
//        }

        #expect(encryptedVault.data.toHexString() == """
        866de95d08a6b24751cdc4e9ab793585614c2062ba690a77762779d1b3c866835ad0b54d1e3f29e9ffc4ad1d26a55e3a198ca9f685225042d331df50d64ad495f2a75c30000c6929c6e38a1bbfa16f0d3b81581c0d8f18ffc1df7ec7de2cdcab847920ca4ce7a9bdf9c900c8853f9f12f19c36b0e3f9e3a79cd90a1be41291e436ffd83df34f31d6387933018eee38fd700ab2d10e5e3f858c3e64f77aafa31df76fda28c5060e4440ebf8358e3f5fa1
        """)
        #expect(encryptedVault.authentication.toHexString() == """
        c69f0292593e8e4c43afb3cbfcc815d0
        """)
        #expect(encryptedVault.encryptionIV.toHexString() == """
        abababababababababababababababababababababababababababababababab
        """)
    }

    // MARK: - Fixed size (VAULT-75)

    /// A backup's size doesn't show how much its vault holds: small ones all come out just under the minimum.
    @Test(arguments: [0, 1, 40])
    func encryptBackupPayload_toFixedSize_fillsTheMinimum(itemCount: Int) throws {
        let sut = makeSUT(key: anyKey(), paddingMode: .toFixedSize(minimum: 32 * 1024))

        let encryptedVault = try sut.encryptBackupPayload(
            items: (0 ..< itemCount).map { _ in anyBackupItem(contentLength: 200) },
            tags: [],
            userDescription: "hello world",
        )

        #expect(fixedSizeWindow(32 * 1024).contains(encryptedVault.data.count))
    }

    /// It lands within the tolerance every time, not just usually. The padding is random, and so are these vaults, of
    /// a random number of items with random contents that fill the minimum or twice it, so every run tries more.
    @Test(arguments: 0 ..< 32)
    func encodeFillingFixedSize_landsWithinTheToleranceEveryTime(run: Int) throws {
        let itemCount = [0, 1, 10, 30, 60][run % 5]
        let payload = VaultBackupPayload(
            version: "1.0.0",
            created: Date(timeIntervalSince1970: 1234),
            userDescription: "hello world",
            tags: [],
            items: (0 ..< itemCount).map { _ in anyBackupItem(contentLength: .random(in: 50 ... 1000)) },
            obfuscationPadding: Data(),
        )

        let encoded = try VaultBackupEncryptor.encodeFillingFixedSize(payload, minimum: 32 * 1024)

        let size = VaultBackupEncryptor.fixedSize(fitting: encoded.data.count, minimum: 32 * 1024)
        #expect(fixedSizeWindow(size).contains(encoded.data.count), "\(itemCount) items")
    }

    /// One that doesn't fit the minimum fills the next power of two, so it shows only roughly how large it is.
    @Test
    func encryptBackupPayload_toFixedSize_largerThanTheMinimum_fillsTheNextPowerOfTwo() throws {
        let sut = makeSUT(key: anyKey(), paddingMode: .toFixedSize(minimum: 32 * 1024))

        let encryptedVault = try sut.encryptBackupPayload(
            items: (0 ..< 40).map { _ in anyBackupItem(contentLength: 1000) },
            tags: [],
            userDescription: "hello world",
        )

        #expect(fixedSizeWindow(64 * 1024).contains(encryptedVault.data.count))
    }

    /// The padding is inside what's encrypted, in the payload's existing field, so the backup restores as any other.
    @Test
    func encryptBackupPayload_toFixedSize_decryptsToTheSameItems() throws {
        let key = KeyData<32>.random()
        let sut = makeSUT(key: VaultKey(key: key, iv: .random()), paddingMode: .toFixedSize(minimum: 32 * 1024))
        let items = (0 ..< 5).map { _ in anyBackupItem(contentLength: 100) }

        let encryptedVault = try sut.encryptBackupPayload(items: items, tags: [], userDescription: "hello world")
        let backup = try VaultBackupDecryptor(key: key).decryptBackupPayload(from: encryptedVault)

        #expect(backup.items == items)
        #expect(backup.userDescription == "hello world")
    }

    @Test
    func fixedSize_isTheMinimumOrTheFirstPowerOfTwoTimesItThatHoldsTheLength() {
        #expect(VaultBackupEncryptor.fixedSize(fitting: 1, minimum: 1024) == 1024)
        #expect(VaultBackupEncryptor.fixedSize(fitting: 1024, minimum: 1024) == 1024)
        #expect(VaultBackupEncryptor.fixedSize(fitting: 1025, minimum: 1024) == 2048)
        #expect(VaultBackupEncryptor.fixedSize(fitting: 5000, minimum: 1024) == 8192)
    }

    @Test
    func encryptBackupPayload_includesKeySaltUnmodifiedInPayload() throws {
        let salt = Data.random(count: 34)
        let sut = makeSUT(key: anyKey(), keygenSalt: salt)

        let encryptedVault = try sut.encryptBackupPayload(items: [], tags: [], userDescription: "hello world")

        #expect(encryptedVault.keygenSalt == salt)
    }
}

// MARK: - Helpers

extension VaultBackupEncryptorTests {
    private func makeSUT(
        clock: any EpochClock = anyClock(),
        key: VaultKey,
        keygenSalt: Data = Data(),
        keygenSignature: String = "my-signature",
        paddingMode: VaultBackupEncryptor.PaddingMode = .none,
    ) -> VaultBackupEncryptor {
        VaultBackupEncryptor(
            clock: clock,
            key: key,
            keygenSalt: keygenSalt,
            keygenSignature: keygenSignature,
            paddingMode: paddingMode,
        )
    }
}

private func anyClock() -> some EpochClock {
    EpochClockMock(currentTime: 1234)
}

private func anyKey() -> VaultKey {
    .init(key: .random(), iv: .random())
}

/// The sizes a backup padded to `size` can be.
private func fixedSizeWindow(_ size: Int) -> ClosedRange<Int> {
    (size - VaultBackupEncryptor.fixedSizeTolerance) ... size
}

/// An item whose contents are random bytes, which compression can't shrink.
private func anyBackupItem(contentLength: Int) -> VaultBackupItem {
    VaultBackupItem(
        id: UUID(),
        createdDate: Date(timeIntervalSince1970: 12345),
        updatedDate: Date(timeIntervalSince1970: 19345),
        relativeOrder: 1000,
        userDescription: "",
        tags: [],
        visibility: .always,
        searchableLevel: .full,
        searchPassphraseSalt: nil,
        searchPassphraseDigest: nil,
        killphraseSalt: nil,
        killphraseDigest: nil,
        lockState: .notLocked,
        item: .encrypted(data: .init(
            version: "1.0.0",
            title: "title",
            data: Data.random(count: contentLength),
            authentication: Data.random(count: 16),
            encryptionIV: Data.random(count: 32),
            keygenSalt: Data.random(count: 32),
            keygenSignature: "sig",
        )),
    )
}
