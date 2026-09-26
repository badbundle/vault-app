import CryptoEngine
import CryptoKit
import Foundation
import Testing
@testable import VaultFeed

struct VaultSlotFileTests {
    /// Cheap parameters, so a derivation takes milliseconds. The format accepts them; calibration never picks them.
    private let parameters = Argon2idParameters(memoryKiB: 64, iterations: 1, parallelism: 1)
    private let mebibyte = 1 << 20
    /// A whole number of milliseconds, so it survives the key box exactly.
    private let date = Date(timeIntervalSince1970: 1_790_000_000.5)
}

// MARK: - Header

extension VaultSlotFileTests {
    @Test
    func init_writesTheHeaderAtItsDocumentedOffsets() throws {
        let file = try VaultSlotFile(kdfParameters: Argon2idParameters(
            memoryKiB: 65536,
            iterations: 24,
            parallelism: 1,
        ))

        let header = file.bytes.prefix(128)
        #expect(header[0 ..< 8] == Data("VLTSLOTS".utf8))
        #expect(header[8 ..< 10] == Data([0x00, 0x01]))
        #expect(header[10 ..< 12] == Data([0x00, 0x10]))
        #expect(header[12 ..< 16] == Data([0x00, 0x10, 0x00, 0x00]))
        #expect(header[16 ..< 18] == Data([0x00, 0x01]))
        #expect(header[18 ..< 22] == Data([0x00, 0x01, 0x00, 0x00]))
        #expect(header[22 ..< 26] == Data([0x00, 0x00, 0x00, 0x18]))
        #expect(header[26] == 0x01)
        #expect(header[27 ..< 32] == Data(count: 5))
        #expect(header[32 ..< 64] == file.header.salt)
        #expect(header[64 ..< 128] == Data(count: 64))
        #expect(file.header.slotSize == mebibyte)
        #expect(file.bytes.count == 128 + 16 * mebibyte)
    }

    @Test
    func init_headersDifferOnlyInTheSalt() throws {
        let first = try makeFile()
        let second = try makeFile()

        #expect(first.header.salt != second.header.salt)
        #expect(first.bytes[0 ..< 32] == second.bytes[0 ..< 32])
        #expect(first.bytes[64 ..< 128] == second.bytes[64 ..< 128])
    }

    @Test
    func init_refusesParametersOutsideTheFormatsLimits() {
        let outside = [
            Argon2idParameters(memoryKiB: 4, iterations: 1, parallelism: 1),
            Argon2idParameters(memoryKiB: 2 << 20, iterations: 1, parallelism: 1),
            Argon2idParameters(memoryKiB: 64, iterations: 0, parallelism: 1),
            Argon2idParameters(memoryKiB: 64, iterations: 33, parallelism: 1),
            Argon2idParameters(memoryKiB: 64, iterations: 1, parallelism: 0),
            Argon2idParameters(memoryKiB: 64, iterations: 1, parallelism: 9),
            Argon2idParameters(memoryKiB: 32, iterations: 1, parallelism: 8),
        ]

        for parameters in outside {
            #expect(throws: VaultSlotFileError.malformed, "\(parameters)") {
                try VaultSlotFile(kdfParameters: parameters)
            }
        }
    }

    @Test
    func initBytes_readsBackTheFileItWasGiven() throws {
        var file = try makeFile()
        try file.createVault(inSlot: 3, rootKey: randomKey(), payload: payload("vault"), wrappedAt: date)

        let read = try VaultSlotFile(bytes: file.bytes)

        #expect(read == file)
    }

    @Test
    func initBytes_readsASliceOfLargerData() throws {
        let file = try makeFile()
        let larger = Data([1, 2, 3]) + file.bytes

        let read = try VaultSlotFile(bytes: larger[3...])

        #expect(read == file)
    }

    @Test
    func initBytes_refusesBytesThatAreNotASlotFile() throws {
        var wrongMagic = try makeFile().bytes
        wrongMagic[0] = UInt8(ascii: "X")

        for bytes in [Data(), Data("VLTSLOTS".utf8), wrongMagic] {
            #expect(throws: VaultSlotFileError.notASlotFile) {
                try VaultSlotFile(bytes: bytes)
            }
        }
    }

    @Test(arguments: [UInt16(0), 2, 0xFFFF])
    func initBytes_refusesOtherVersionsBeforeReadingAnythingElse(version: UInt16) throws {
        var bytes = try makeFile().bytes
        bytes.replaceBigEndianInteger(at: 8, with: version)
        // A newer layout could put anything after the version.
        bytes.replaceSubrange(10 ..< 128, with: Data(repeating: 0xAB, count: 118))
        bytes.removeLast(12345)

        #expect(throws: VaultSlotFileError.unsupportedVersion(version)) {
            try VaultSlotFile(bytes: bytes)
        }
    }

    @Test
    func initBytes_readsTheVersionOfAFileTooShortForAHeader() throws {
        let newer = Data("VLTSLOTS".utf8) + [0x00, 0x02]
        let current = Data("VLTSLOTS".utf8) + [0x00, 0x01] + Data(count: 100)

        #expect(throws: VaultSlotFileError.unsupportedVersion(2)) {
            try VaultSlotFile(bytes: newer)
        }
        #expect(throws: VaultSlotFileError.malformed) {
            try VaultSlotFile(bytes: current)
        }
    }

    @Test(arguments: HeaderChange.malformed)
    func initBytes_refusesAMalformedHeader(change: HeaderChange) throws {
        var bytes = try makeFile().bytes
        bytes.replaceSubrange(change.offset ..< change.offset + change.bytes.count, with: change.bytes)

        #expect(throws: VaultSlotFileError.malformed) {
            try VaultSlotFile(bytes: bytes)
        }
    }

    @Test
    func initBytes_refusesAFileOfTheWrongLength() throws {
        let bytes = try makeFile().bytes

        for wrongLength in [bytes.dropLast(), bytes + Data([0]), bytes.prefix(128)] {
            #expect(throws: VaultSlotFileError.malformed) {
                try VaultSlotFile(bytes: wrongLength)
            }
        }
    }
}

// MARK: - Password and device-key wraps

extension VaultSlotFileTests {
    @Test(arguments: VaultSlotCompression.allCases)
    func createVault_roundTripsThePayloadAndTheKeyBox(compression: VaultSlotCompression) throws {
        var file = try makeFile()
        let rootKey = randomKey()
        let payload = VaultSlotPayload(version: 7, data: Data(String(repeating: "vault item ", count: 1000).utf8))

        let created = try file.createVault(
            inSlot: 5,
            rootKey: rootKey,
            payload: payload,
            wrappedAt: date,
            compression: compression,
        )

        let read = try VaultSlotFile(bytes: file.bytes)
        let opened = try read.openSlot(5, with: rootKey)
        #expect(opened.index == 5)
        #expect(opened.generation == 1)
        #expect(opened.wrappedAt == date)
        #expect(created.index == 5)
        #expect(created.generation == 1)
        #expect(created.wrappedAt == date)
        #expect(try read.openPayload(of: opened) == payload)
    }

    @Test(arguments: VaultSlotCompression.allCases)
    func createVault_roundTripsAnEmptyPayload(compression: VaultSlotCompression) throws {
        var file = try makeFile()
        let rootKey = randomKey()
        let payload = VaultSlotPayload(version: 1, data: Data())

        try file.createVault(inSlot: 0, rootKey: rootKey, payload: payload, wrappedAt: date, compression: compression)

        #expect(try file.openPayload(of: file.openSlot(0, with: rootKey)) == payload)
    }

    @Test
    func createVault_roundTripsAPayloadLargerThanTheCompressionBuffer() throws {
        var file = try makeFile()
        let rootKey = randomKey()
        let items = (0 ..< 5000).map { #"{"id":"\#(UUID())","issuer":"Issuer \#($0)"}"# }
        let payload = VaultSlotPayload(version: 1, data: Data("[\(items.joined(separator: ","))]".utf8))

        try file.createVault(inSlot: 15, rootKey: rootKey, payload: payload, wrappedAt: date)

        #expect(payload.data.count > 4 * (1 << 16))
        #expect(try file.openPayload(of: file.openSlot(15, with: rootKey)) == payload)
    }

    @Test
    func openSlot_passwordOpensOnlyTheSlotItCreated() throws {
        var file = try makeFile()
        let password = Data("correct horse battery staple".utf8)
        try file.createVault(
            inSlot: 9,
            rootKey: file.header.passwordKey(for: password),
            payload: payload("real"),
            wrappedAt: date,
        )

        let read = try VaultSlotFile(bytes: file.bytes)
        let rootKey = try read.header.passwordKey(for: password)
        let opened = VaultSlotFile.slotIndices.filter { (try? read.openSlot($0, with: rootKey)) != nil }

        #expect(opened == [9])
        #expect(try read.openPayload(of: read.openSlot(9, with: rootKey)) == payload("real"))
    }

    @Test
    func openSlot_wrongPasswordOpensNoSlot() throws {
        var file = try makeFile()
        try file.createVault(
            inSlot: 9,
            rootKey: file.header.passwordKey(for: Data("correct horse battery staple".utf8)),
            payload: payload("real"),
            wrappedAt: date,
        )

        let wrongKey = try file.header.passwordKey(for: Data("correct horse battery stapler".utf8))

        for index in VaultSlotFile.slotIndices {
            #expect(throws: VaultSlotFileError.slotDidNotOpen) {
                try file.openSlot(index, with: wrongKey)
            }
        }
    }

    @Test
    func openSlot_eachPasswordOpensItsOwnSlot() throws {
        var file = try makeFile()
        let first = Data("first password".utf8)
        let second = Data("second password".utf8)
        try file.createVault(
            inSlot: 2,
            rootKey: file.header.passwordKey(for: first),
            payload: payload("first"),
            wrappedAt: date,
        )
        try file.createVault(
            inSlot: 13,
            rootKey: file.header.passwordKey(for: second),
            payload: payload("second"),
            wrappedAt: date,
        )

        let firstKey = try file.header.passwordKey(for: first)
        let secondKey = try file.header.passwordKey(for: second)

        #expect(VaultSlotFile.slotIndices.filter { (try? file.openSlot($0, with: firstKey)) != nil } == [2])
        #expect(VaultSlotFile.slotIndices.filter { (try? file.openSlot($0, with: secondKey)) != nil } == [13])
        #expect(try file.openPayload(of: file.openSlot(2, with: firstKey)) == payload("first"))
        #expect(try file.openPayload(of: file.openSlot(13, with: secondKey)) == payload("second"))
    }

    @Test
    func openSlot_newFileOpensNoSlot() throws {
        let file = try makeFile()
        let rootKey = randomKey()

        for index in VaultSlotFile.slotIndices {
            #expect(throws: VaultSlotFileError.slotDidNotOpen) {
                try file.openSlot(index, with: rootKey)
            }
        }
    }

    @Test
    func openSlot_deviceKeyOpensOnlyItsSlot() throws {
        var file = try makeFile()
        let deviceKey = VaultSlotRootKey.device(SymmetricKey(size: .bits256))
        try file.createVault(inSlot: 4, rootKey: deviceKey, payload: payload("device"), wrappedAt: date)

        let otherDeviceKey = VaultSlotRootKey.device(SymmetricKey(size: .bits256))

        #expect(try file.openPayload(of: file.openSlot(4, with: deviceKey)) == payload("device"))
        #expect(throws: VaultSlotFileError.slotDidNotOpen) {
            try file.openSlot(4, with: otherDeviceKey)
        }
    }

    @Test
    func openSlot_passwordAndDeviceKeysWithTheSameBytesDoNotOpenEachOthersSlots() throws {
        var file = try makeFile()
        let key = SymmetricKey(size: .bits256)
        try file.createVault(
            inSlot: 1,
            rootKey: .password(derivedKey: key),
            payload: payload("password"),
            wrappedAt: date,
        )
        try file.createVault(inSlot: 2, rootKey: .device(key), payload: payload("device"), wrappedAt: date)

        #expect(try file.openPayload(of: file.openSlot(1, with: .password(derivedKey: key))) == payload("password"))
        #expect(try file.openPayload(of: file.openSlot(2, with: .device(key))) == payload("device"))
        #expect(throws: VaultSlotFileError.slotDidNotOpen) {
            try file.openSlot(1, with: .device(key))
        }
        #expect(throws: VaultSlotFileError.slotDidNotOpen) {
            try file.openSlot(2, with: .password(derivedKey: key))
        }
    }

    @Test
    func createVault_givesEachSlotItsOwnNonceWrapKeyAndDataKey() throws {
        var file = try makeFile()
        let rootKey = randomKey()

        let first = try file.createVault(inSlot: 6, rootKey: rootKey, payload: payload("a"), wrappedAt: date)
        let second = try file.createVault(inSlot: 7, rootKey: rootKey, payload: payload("a"), wrappedAt: date)

        #expect(first.slotNonce != second.slotNonce)
        #expect(bytes(of: first.wrapKey) != bytes(of: second.wrapKey))
        #expect(bytes(of: first.dataKey) != bytes(of: second.dataKey))
    }

    @Test
    func passwordKey_isArgon2idOfThePasswordWithTheHeadersParametersAndSalt() throws {
        let file = try makeFile()
        let password = Data("password".utf8)

        let rootKey = try file.header.passwordKey(for: password)

        let expected = try Argon2idKeyDeriver<32>(parameters: parameters).key(
            password: password,
            salt: file.header.salt,
        )
        #expect(rootKey.kind == .password)
        #expect(bytes(of: rootKey.key) == expected.data)
    }

    @Test
    func wrapKey_isHKDFOfTheRootKeyWithTheSlotNonceAndKindLabel() {
        let key = SymmetricKey(size: .bits256)
        let nonce = Data(repeating: 0x42, count: 32)

        let passwordWrapKey = VaultSlotRootKey.password(derivedKey: key).wrapKey(slotNonce: nonce)
        let deviceWrapKey = VaultSlotRootKey.device(key).wrapKey(slotNonce: nonce)

        let expectedPassword = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: nonce,
            info: Data("vault.slot.wrap.password.v1".utf8),
            outputByteCount: 32,
        )
        let expectedDevice = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: nonce,
            info: Data("vault.slot.wrap.device.v1".utf8),
            outputByteCount: 32,
        )
        #expect(bytes(of: passwordWrapKey) == bytes(of: expectedPassword))
        #expect(bytes(of: deviceWrapKey) == bytes(of: expectedDevice))
    }
}

// MARK: - AAD binding and tampering

extension VaultSlotFileTests {
    @Test
    func openSlot_slotCopiedToAnotherIndexDoesNotOpen() throws {
        var file = try makeFile()
        let rootKey = randomKey()
        try file.createVault(inSlot: 4, rootKey: rootKey, payload: payload("vault"), wrappedAt: date)
        var bytes = file.bytes
        bytes.replaceSubrange(file.slotRange(11), with: file.bytes[file.slotRange(4)])

        let moved = try VaultSlotFile(bytes: bytes)

        #expect(throws: VaultSlotFileError.slotDidNotOpen) {
            try moved.openSlot(11, with: rootKey)
        }
        #expect(try moved.openPayload(of: moved.openSlot(4, with: rootKey)) == payload("vault"))
    }

    @Test
    func openSlot_slotCopiedIntoAnotherFileDoesNotOpen() throws {
        var file = try makeFile()
        let rootKey = randomKey()
        try file.createVault(inSlot: 4, rootKey: rootKey, payload: payload("vault"), wrappedAt: date)
        let other = try makeFile()
        var bytes = other.bytes
        bytes.replaceSubrange(other.slotRange(4), with: file.bytes[file.slotRange(4)])

        let transplanted = try VaultSlotFile(bytes: bytes)

        #expect(throws: VaultSlotFileError.slotDidNotOpen) {
            try transplanted.openSlot(4, with: rootKey)
        }
    }

    @Test
    func changingAnyHeaderByteStopsTheSlotOpening() throws {
        var file = try makeFile()
        let rootKey = randomKey()
        try file.createVault(inSlot: 6, rootKey: rootKey, payload: payload("vault"), wrappedAt: date)
        var bytes = file.bytes
        #expect(opensSlot(6, in: bytes, with: rootKey))

        for offset in 0 ..< VaultSlotFile.Header.length {
            bytes[offset] ^= 0x01
            #expect(!opensSlot(6, in: bytes, with: rootKey), "header byte \(offset)")
            bytes[offset] ^= 0x01
        }
    }

    @Test
    func changingAnyNonceOrKeyBoxByteStopsTheSlotOpening() throws {
        var file = try makeFile()
        let rootKey = randomKey()
        try file.createVault(inSlot: 6, rootKey: rootKey, payload: payload("vault"), wrappedAt: date)
        var bytes = file.bytes
        let slotStart = file.slotRange(6).lowerBound

        for offset in slotStart ..< slotStart + 32 + 84 {
            bytes[offset] ^= 0x01
            let tampered = try VaultSlotFile(bytes: bytes)
            #expect(throws: VaultSlotFileError.slotDidNotOpen, "slot byte \(offset - slotStart)") {
                try tampered.openSlot(6, with: rootKey)
            }
            bytes[offset] ^= 0x01
        }
    }

    @Test
    func changingAnyBodyByteStopsThePayloadOpening() throws {
        var file = try makeFile()
        let rootKey = randomKey()
        try file.createVault(inSlot: 6, rootKey: rootKey, payload: payload("vault"), wrappedAt: date)
        var bytes = file.bytes
        let slot = file.slotRange(6)
        let bodyStart = slot.lowerBound + 116
        // Every byte of the body box's nonce and body header, every byte of its tag, and a spread in between.
        let offsets = Array(bodyStart ..< bodyStart + 64) + Array(stride(
            from: bodyStart + 64,
            to: slot.upperBound - 64,
            by: 4099,
        ))
            + Array(slot.upperBound - 64 ..< slot.upperBound)

        for offset in offsets {
            bytes[offset] ^= 0x01
            let tampered = try VaultSlotFile(bytes: bytes)
            let opened = try tampered.openSlot(6, with: rootKey)
            #expect(throws: VaultSlotFileError.bodyDidNotOpen, "body byte \(offset - bodyStart)") {
                try tampered.openPayload(of: opened)
            }
            bytes[offset] ^= 0x01
        }
    }
}

// MARK: - Boxes that open but break the format

extension VaultSlotFileTests {
    /// Shorter than the smallest body box (the seal overhead and the body header), or running past the end of a
    /// 1 MiB slot, whose body starts 116 bytes in.
    @Test(arguments: [UInt64(0), 43, (1 << 20) - 116 + 1, .max])
    func openSlot_refusesAKeyBoxWhoseBodyLengthDoesNotFitTheSlot(bodyLength: UInt64) throws {
        var file = try makeFile()
        let rootKey = randomKey()
        let created = try file.createVault(inSlot: 5, rootKey: rootKey, payload: payload("vault"), wrappedAt: date)
        var keyBox = bytes(of: created.dataKey)
        keyBox.appendBigEndianInteger(bodyLength)
        keyBox.appendBigEndianInteger(created.generation)
        keyBox.appendBigEndianInteger(UInt64(0))

        let changed = try replacingKeyBox(of: created, in: file, withSealed: keyBox)

        #expect(throws: VaultSlotFileError.slotDidNotOpen) {
            try changed.openSlot(5, with: rootKey)
        }
    }

    @Test
    func openPayload_readsABodySealedByTheTestHelper() throws {
        let (file, slot) = try fileWithBody { plaintext in
            plaintext.replaceBigEndianInteger(at: 0, with: UInt32(9))
            plaintext.replaceBigEndianInteger(at: 8, with: UInt64(3))
            plaintext.replaceSubrange(16 ..< 19, with: Data("abc".utf8))
        }

        #expect(try file.openPayload(of: slot) == payload("abc", version: 9))
    }

    @Test(arguments: [UInt32(2), .max])
    func openPayload_refusesACompressionItDoesNotKnow(compression: UInt32) throws {
        let (file, slot) = try fileWithBody { plaintext in
            plaintext.replaceBigEndianInteger(at: 4, with: compression)
        }

        #expect(throws: VaultSlotFileError.unsupportedCompression(compression)) {
            try file.openPayload(of: slot)
        }
    }

    @Test
    func openPayload_refusesACompressedLengthLongerThanTheBody() throws {
        let (file, slot) = try fileWithBody { plaintext in
            plaintext.replaceBigEndianInteger(at: 8, with: UInt64(plaintext.count - 16 + 1))
        }

        #expect(throws: VaultSlotFileError.bodyDidNotOpen) {
            try file.openPayload(of: slot)
        }
    }

    @Test
    func lzfse_refusesAStreamThatIsCutShortOrIsNotLZFSE() throws {
        let compressed = try VaultSlotCompression.lzfse.compress(Data(String(repeating: "vault ", count: 20000).utf8))

        for broken in [Data(), compressed.prefix(compressed.count / 2), Data(repeating: 0xAB, count: 256)] {
            #expect(throws: VaultSlotFileError.compressionFailed) {
                try VaultSlotCompression.lzfse.decompress(broken)
            }
        }
    }
}

// MARK: - Saving

extension VaultSlotFileTests {
    @Test
    func seal_replacesThePayloadAtTheNextGeneration() throws {
        var file = try makeFile()
        let rootKey = randomKey()
        let created = try file.createVault(inSlot: 0, rootKey: rootKey, payload: payload("first"), wrappedAt: date)

        let sealed = try file.seal(payload("second", version: 2), in: created)

        let read = try VaultSlotFile(bytes: file.bytes)
        let opened = try read.openSlot(0, with: rootKey)
        #expect(sealed.generation == 2)
        #expect(opened.generation == 2)
        #expect(opened.wrappedAt == date)
        #expect(try read.openPayload(of: opened) == payload("second", version: 2))
    }

    @Test
    func seal_leavesTheHeaderAndEveryOtherSlotAsTheyWere() throws {
        var file = try makeFile()
        let created = try file.createVault(inSlot: 7, rootKey: randomKey(), payload: payload("first"), wrappedAt: date)
        let before = file.bytes

        try file.seal(payload("first"), in: created)

        #expect(file.bytes[0 ..< 128] == before[0 ..< 128])
        for index in VaultSlotFile.slotIndices where index != 7 {
            #expect(file.bytes[file.slotRange(index)] == before[file.slotRange(index)], "slot \(index)")
        }
        let slotStart = file.slotRange(7).lowerBound
        // The same slot nonce, but fresh box nonces, even for the same payload.
        #expect(file.bytes[slotStart ..< slotStart + 32] == before[slotStart ..< slotStart + 32])
        #expect(file.bytes[slotStart + 32 ..< slotStart + 116] != before[slotStart + 32 ..< slotStart + 116])
        #expect(file.bytes[slotStart + 116 ..< slotStart + 128] != before[slotStart + 116 ..< slotStart + 128])
    }

    @Test
    func seal_refusesASlotWrittenSinceItWasOpened() throws {
        var file = try makeFile()
        let created = try file.createVault(inSlot: 3, rootKey: randomKey(), payload: payload("first"), wrappedAt: date)
        try file.seal(payload("second"), in: created)
        let before = file.bytes

        #expect(throws: VaultSlotFileError.slotChanged) {
            try file.seal(payload("stale"), in: created)
        }
        #expect(throws: VaultSlotFileError.slotChanged) {
            try file.rewrap(created, with: randomKey(), wrappedAt: date)
        }
        #expect(file.bytes == before)
    }

    @Test
    func seal_refusesASlotReplacedByAnotherVault() throws {
        var file = try makeFile()
        let created = try file.createVault(inSlot: 3, rootKey: randomKey(), payload: payload("first"), wrappedAt: date)
        try file.createVault(inSlot: 3, rootKey: randomKey(), payload: payload("replacement"), wrappedAt: date)

        #expect(throws: VaultSlotFileError.slotChanged) {
            try file.seal(payload("stale"), in: created)
        }
    }

    @Test
    func reopen_readsTheCurrentKeyBoxWithTheKeptWrapKey() throws {
        var file = try makeFile()
        let created = try file.createVault(inSlot: 8, rootKey: randomKey(), payload: payload("first"), wrappedAt: date)
        try file.seal(payload("second"), in: created)

        let current = try VaultSlotFile(bytes: file.bytes).reopen(created)
        #expect(current.generation == 2)

        try file.rewrap(current, with: randomKey(), wrappedAt: date)
        #expect(throws: VaultSlotFileError.slotDidNotOpen) {
            try file.reopen(created)
        }
    }
}

// MARK: - Growth

extension VaultSlotFileTests {
    @Test
    func seal_growsEverySlotWhenThePayloadDoesNotFit() throws {
        var file = try makeFile()
        let firstKey = randomKey()
        let secondKey = VaultSlotRootKey.device(SymmetricKey(size: .bits256))
        try file.createVault(inSlot: 2, rootKey: firstKey, payload: payload("first"), wrappedAt: date)
        let second = try file.createVault(inSlot: 11, rootKey: secondKey, payload: payload("second"), wrappedAt: date)
        let before = file
        let large = VaultSlotPayload(version: 1, data: SlotRandom.bytes(count: mebibyte))

        try file.seal(large, in: second, compression: .none)

        let read = try VaultSlotFile(bytes: file.bytes)
        #expect(read.header.slotSize == 2 * mebibyte)
        #expect(read.bytes.count == 128 + 16 * 2 * mebibyte)
        #expect(read.header.authenticatedBytes == before.header.authenticatedBytes)
        for index in VaultSlotFile.slotIndices where index != 11 {
            let grown = read.bytes[read.slotRange(index)]
            #expect(grown.prefix(mebibyte) == before.bytes[before.slotRange(index)], "slot \(index)")
            #expect(looksRandom(grown.suffix(mebibyte)), "fill after slot \(index)")
        }
        let first = try read.openSlot(2, with: firstKey)
        let grownSecond = try read.openSlot(11, with: secondKey)
        #expect(try read.openPayload(of: first) == payload("first"))
        #expect(try read.openPayload(of: grownSecond) == large)
        #expect(first.bodyLength == mebibyte - 116)
        #expect(grownSecond.bodyLength == 2 * mebibyte - 116)
    }

    @Test
    func seal_afterGrowthFillsTheLargerSlot() throws {
        var file = try makeFile()
        let firstKey = randomKey()
        let first = try file.createVault(inSlot: 2, rootKey: firstKey, payload: payload("first"), wrappedAt: date)
        try file.createVault(
            inSlot: 11,
            rootKey: randomKey(),
            payload: VaultSlotPayload(version: 1, data: SlotRandom.bytes(count: mebibyte)),
            wrappedAt: date,
            compression: .none,
        )

        let sealed = try file.seal(payload("first, again"), in: file.reopen(first))

        #expect(file.header.slotSize == 2 * mebibyte)
        #expect(sealed.bodyLength == 2 * mebibyte - 116)
        #expect(try file.openPayload(of: file.openSlot(2, with: firstKey)) == payload("first, again"))
    }

    @Test
    func seal_growsOnlyPastTheSlotsCapacity() throws {
        let capacity = VaultSlotFile.payloadCapacity(slotSize: mebibyte)
        var file = try makeFile()
        let rootKey = randomKey()

        let created = try file.createVault(
            inSlot: 0,
            rootKey: rootKey,
            payload: VaultSlotPayload(version: 1, data: SlotRandom.bytes(count: capacity)),
            wrappedAt: date,
            compression: .none,
        )
        #expect(capacity == mebibyte - 160)
        #expect(file.header.slotSize == mebibyte)

        let fits = VaultSlotPayload(version: 1, data: SlotRandom.bytes(count: capacity + 1))
        try file.seal(fits, in: created, compression: .none)
        #expect(file.header.slotSize == 2 * mebibyte)
        #expect(try file.openPayload(of: file.openSlot(0, with: rootKey)) == fits)
    }

    @Test
    func seal_refusesAPayloadLargerThanTheLargestSlot() throws {
        var file = try makeFile()
        let created = try file.createVault(inSlot: 0, rootKey: randomKey(), payload: payload("first"), wrappedAt: date)
        let before = file.bytes
        let tooLarge = Data(count: VaultSlotFile.payloadCapacity(slotSize: VaultSlotFile.maximumSlotSize) + 1)

        #expect(throws: VaultSlotFileError.payloadTooLarge) {
            try file.seal(VaultSlotPayload(version: 1, data: tooLarge), in: created, compression: .none)
        }
        #expect(file.bytes == before)
    }

    @Test
    func slotSize_doublesUntilThePayloadFitsAndNeverShrinks() {
        let mib = mebibyte
        func capacity(_ size: Int) -> Int {
            VaultSlotFile.payloadCapacity(slotSize: size)
        }

        #expect(VaultSlotFile.slotSize(fittingCompressedLength: 0, from: mib) == mib)
        #expect(VaultSlotFile.slotSize(fittingCompressedLength: capacity(mib), from: mib) == mib)
        #expect(VaultSlotFile.slotSize(fittingCompressedLength: capacity(mib) + 1, from: mib) == 2 * mib)
        #expect(VaultSlotFile.slotSize(fittingCompressedLength: capacity(8 * mib) + 1, from: mib) == 16 * mib)
        #expect(VaultSlotFile.slotSize(fittingCompressedLength: capacity(64 * mib), from: mib) == 64 * mib)
        #expect(VaultSlotFile.slotSize(fittingCompressedLength: capacity(64 * mib) + 1, from: mib) == nil)
        #expect(VaultSlotFile.slotSize(fittingCompressedLength: 0, from: 4 * mib) == 4 * mib)
    }
}

// MARK: - Rewrapping

extension VaultSlotFileTests {
    @Test
    func rewrap_movesTheSlotToTheNewKeyWithoutTouchingTheBody() throws {
        var file = try makeFile()
        let passwordKey = randomKey()
        let deviceKey = VaultSlotRootKey.device(SymmetricKey(size: .bits256))
        let created = try file.createVault(inSlot: 14, rootKey: passwordKey, payload: payload("vault"), wrappedAt: date)
        let before = file.bytes
        let later = Date(timeIntervalSince1970: 1_800_000_000.25)

        let rewrapped = try file.rewrap(created, with: deviceKey, wrappedAt: later)

        let slot = file.slotRange(14)
        #expect(file
            .bytes[slot.lowerBound ..< slot.lowerBound + 32] == before[slot.lowerBound ..< slot.lowerBound + 32])
        #expect(file
            .bytes[slot.lowerBound + 32 ..< slot.lowerBound + 116] !=
            before[slot.lowerBound + 32 ..< slot.lowerBound + 116])
        #expect(file
            .bytes[slot.lowerBound + 116 ..< slot.upperBound] == before[slot.lowerBound + 116 ..< slot.upperBound])
        let read = try VaultSlotFile(bytes: file.bytes)
        #expect(throws: VaultSlotFileError.slotDidNotOpen) {
            try read.openSlot(14, with: passwordKey)
        }
        let opened = try read.openSlot(14, with: deviceKey)
        #expect(rewrapped.generation == 2)
        #expect(opened.generation == 2)
        #expect(opened.wrappedAt == later)
        #expect(try read.openPayload(of: opened) == payload("vault"))
    }

    @Test
    func rewrap_changesThePassword() throws {
        var file = try makeFile()
        let oldPassword = Data("old password".utf8)
        let newPassword = Data("new password".utf8)
        let created = try file.createVault(
            inSlot: 12,
            rootKey: file.header.passwordKey(for: oldPassword),
            payload: payload("vault"),
            wrappedAt: date,
        )

        try file.rewrap(created, with: file.header.passwordKey(for: newPassword), wrappedAt: date)

        let read = try VaultSlotFile(bytes: file.bytes)
        let oldKey = try read.header.passwordKey(for: oldPassword)
        let newKey = try read.header.passwordKey(for: newPassword)
        #expect(VaultSlotFile.slotIndices.filter { (try? read.openSlot($0, with: oldKey)) != nil }.isEmpty)
        #expect(try read.openPayload(of: read.openSlot(12, with: newKey)) == payload("vault"))
    }
}

// MARK: - Equal slot lengths

extension VaultSlotFileTests {
    @Test
    func everyFileIsTheSameLengthAndEveryBodyFillsItsSlot() throws {
        let capacity = VaultSlotFile.payloadCapacity(slotSize: mebibyte)
        let payloads = [
            VaultSlotPayload(version: 1, data: Data()),
            payload("small"),
            VaultSlotPayload(version: 1, data: SlotRandom.bytes(count: capacity / 2)),
            VaultSlotPayload(version: 1, data: SlotRandom.bytes(count: capacity)),
        ]
        let empty = try makeFile()
        #expect(empty.bytes.count == 128 + 16 * mebibyte)

        for payload in payloads {
            var file = try makeFile()
            let rootKey = randomKey()
            try file.createVault(inSlot: 5, rootKey: rootKey, payload: payload, wrappedAt: date, compression: .none)

            #expect(file.bytes.count == empty.bytes.count)
            #expect(try file.openSlot(5, with: rootKey).bodyLength == mebibyte - 116)
        }
    }
}

// MARK: - No plaintext leakage

extension VaultSlotFileTests {
    @Test(arguments: VaultSlotCompression.allCases)
    func fileNeverContainsThePayloadThePasswordOrAnyKey(compression: VaultSlotCompression) throws {
        let marker = "PLAINTEXT-MARKER-\(UUID().uuidString)"
        let items = (0 ..< 200).map { #"{"issuer":"\#(marker)-\#($0)","secret":"\#(marker)"}"# }
        let payload = VaultSlotPayload(version: 1, data: Data("[\(items.joined(separator: ","))]".utf8))
        let password = Data("password-\(UUID().uuidString)".utf8)
        var file = try makeFile()
        let rootKey = try file.header.passwordKey(for: password)

        let created = try file.createVault(
            inSlot: 10,
            rootKey: rootKey,
            payload: payload,
            wrappedAt: date,
            compression: compression,
        )
        let sealed = try file.seal(payload, in: created, compression: compression)

        #expect(try file.openPayload(of: sealed) == payload)
        let secrets = [
            ("marker", Data(marker.utf8)),
            ("marker prefix", Data("PLAINTEXT-MARKER-".utf8)),
            ("field name", Data(#""issuer""#.utf8)),
            ("password", password),
            ("password key", bytes(of: rootKey.key)),
            ("wrap key", bytes(of: sealed.wrapKey)),
            ("data key", bytes(of: sealed.dataKey)),
        ]
        for (name, secret) in secrets {
            #expect(file.bytes.range(of: secret) == nil, "\(name)")
        }
    }

    @Test
    func everySlotLooksRandomWhetherOrNotItHoldsAVault() throws {
        var file = try makeFile()
        // Mostly zero fill before sealing, and stored without compression.
        try file.createVault(
            inSlot: 3,
            rootKey: randomKey(),
            payload: payload("small"),
            wrappedAt: date,
            compression: .none,
        )

        for index in VaultSlotFile.slotIndices {
            #expect(looksRandom(file.bytes[file.slotRange(index)]), "slot \(index)")
        }
    }
}

// MARK: - Helpers

extension VaultSlotFileTests {
    struct HeaderChange: Sendable, CustomTestStringConvertible {
        let name: String
        let offset: Int
        let bytes: [UInt8]

        var testDescription: String {
            name
        }

        static let malformed = [
            HeaderChange(name: "slot count 15", offset: 10, bytes: [0x00, 0x0F]),
            HeaderChange(name: "slot size 512 KiB", offset: 12, bytes: [0x00, 0x08, 0x00, 0x00]),
            HeaderChange(name: "slot size not a power of two", offset: 12, bytes: [0x00, 0x18, 0x00, 0x00]),
            HeaderChange(name: "slot size 2 MiB, file 1 MiB", offset: 12, bytes: [0x00, 0x20, 0x00, 0x00]),
            HeaderChange(name: "slot size 128 MiB", offset: 12, bytes: [0x08, 0x00, 0x00, 0x00]),
            HeaderChange(name: "KDF id 2", offset: 16, bytes: [0x00, 0x02]),
            HeaderChange(name: "memory 4 KiB", offset: 18, bytes: [0x00, 0x00, 0x00, 0x04]),
            HeaderChange(name: "memory 2 GiB", offset: 18, bytes: [0x00, 0x20, 0x00, 0x00]),
            HeaderChange(name: "passes 0", offset: 22, bytes: [0x00, 0x00, 0x00, 0x00]),
            HeaderChange(name: "passes 33", offset: 22, bytes: [0x00, 0x00, 0x00, 0x21]),
            HeaderChange(name: "lanes 0", offset: 26, bytes: [0x00]),
            HeaderChange(name: "lanes 9", offset: 26, bytes: [0x09]),
            HeaderChange(name: "gap not zero", offset: 27, bytes: [0x01]),
            HeaderChange(name: "reserved not zero", offset: 127, bytes: [0x01]),
        ]
    }

    private func makeFile() throws -> VaultSlotFile {
        try VaultSlotFile(kdfParameters: parameters)
    }

    private func randomKey() -> VaultSlotRootKey {
        .password(derivedKey: SymmetricKey(size: .bits256))
    }

    private func payload(_ string: String, version: UInt32 = 1) -> VaultSlotPayload {
        VaultSlotPayload(version: version, data: Data(string.utf8))
    }

    private func bytes(of key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// The file with the slot's key box replaced by `plaintext`, sealed with the slot's wrap key the way the app
    /// seals it. It stands in for a key box written by a broken or newer app.
    private func replacingKeyBox(
        of slot: VaultSlotFile.OpenedSlot,
        in file: VaultSlotFile,
        withSealed plaintext: Data,
    ) throws -> VaultSlotFile {
        let box = try AES.GCM.seal(
            plaintext,
            using: slot.wrapKey,
            authenticating: file.associatedData(slot: slot.index, slotNonce: slot.slotNonce),
        )
        var bytes = file.bytes
        let start = file.slotRange(slot.index).lowerBound + VaultSlotFile.slotNonceLength
        try bytes.replaceSubrange(start ..< start + VaultSlotFile.keyBoxLength, with: #require(box.combined))
        return try VaultSlotFile(bytes: bytes)
    }

    /// A file with a vault in slot 5 whose body is a zero-length, uncompressed, version 1 payload, changed by
    /// `change` and sealed with the slot's data key the way the app seals it. It stands in for a body written by a
    /// broken or newer app.
    private func fileWithBody(
        _ change: (inout Data) -> Void,
    ) throws -> (VaultSlotFile, VaultSlotFile.OpenedSlot) {
        var file = try makeFile()
        let rootKey = randomKey()
        let slot = try file.createVault(inSlot: 5, rootKey: rootKey, payload: payload("vault"), wrappedAt: date)
        var plaintext = Data(count: slot.bodyLength - VaultSlotFile.sealOverhead)
        plaintext.replaceBigEndianInteger(at: 0, with: UInt32(1))
        plaintext.replaceBigEndianInteger(at: 4, with: VaultSlotCompression.none.rawValue)
        change(&plaintext)
        let box = try AES.GCM.seal(
            plaintext,
            using: slot.dataKey,
            authenticating: file.associatedData(slot: slot.index, slotNonce: slot.slotNonce),
        )
        var bytes = file.bytes
        let start = file.slotRange(slot.index).lowerBound + VaultSlotFile.bodyOffset
        try bytes.replaceSubrange(start ..< start + slot.bodyLength, with: #require(box.combined))
        let changed = try VaultSlotFile(bytes: bytes)
        return try (changed, changed.openSlot(slot.index, with: rootKey))
    }

    /// Whether the slot's key box and body both open. The file isn't kept, so the caller can keep changing
    /// `bytes` in place.
    private func opensSlot(_ index: Int, in bytes: Data, with rootKey: VaultSlotRootKey) -> Bool {
        guard let file = try? VaultSlotFile(bytes: bytes), let slot = try? file.openSlot(index, with: rootKey) else {
            return false
        }
        return (try? file.openPayload(of: slot)) != nil
    }

    /// Whether every byte value occurs within 10% of the expected count, which for a mebibyte is about 6.4
    /// standard deviations either side. Zero fill left unencrypted, or any structure, fails it.
    private func looksRandom(_ bytes: Data) -> Bool {
        var counts = [Int](repeating: 0, count: 256)
        bytes.withUnsafeBytes { buffer in
            for byte in buffer {
                counts[Int(byte)] += 1
            }
        }
        let expected = bytes.count / 256
        return counts.allSatisfy { abs($0 - expected) <= expected / 10 }
    }
}
