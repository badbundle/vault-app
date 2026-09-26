import CryptoEngine
import CryptoKit
import Foundation

extension VaultSlotFile {
    /// The file's plaintext header. It's the same on every install apart from the salt, and the slot size after
    /// growth.
    ///
    /// ```
    /// 0   8  magic "VLTSLOTS"
    /// 8   2  format version
    /// 10  2  slot count = 16
    /// 12  4  slot size in bytes (1 MiB × 2^k)
    /// 16  2  KDF id (1 = Argon2id)
    /// 18  4  Argon2 memory KiB    22  4  Argon2 passes    26  1  Argon2 lanes    27  5  zero
    /// 32  32 salt
    /// 64  64 reserved, zero
    /// ```
    ///
    /// Integers are big-endian.
    ///
    /// **Versions.** The version is read straight after the magic, and a file with any version but this one is
    /// refused with `VaultSlotFileError.unsupportedVersion(_:)` before anything else is read. A change to the layout
    /// of the header or the slots gets a new version, which can use the reserved bytes. Changes inside the payload
    /// don't need one: the body records its own payload version and compression.
    public struct Header: Equatable, Sendable {
        /// The header's length in bytes.
        public static let length = 128
        /// The format version this app reads and writes.
        public static let currentVersion: UInt16 = 1
        public static let saltLength = 32

        static let magic = Data("VLTSLOTS".utf8)
        static let argon2idKDF: UInt16 = 1

        /// Argon2id parameters are refused outside these, before anything is derived, so a changed header can't
        /// make unlocking run for hours or ask for gigabytes. Calibration picks from well inside them.
        static let memoryKiBRange: ClosedRange<UInt32> = 8 ... 1 << 20
        static let passesRange: ClosedRange<UInt32> = 1 ... 32
        static let lanesRange: ClosedRange<UInt32> = 1 ... 8

        /// The size of every slot, in bytes: 1 MiB × 2^k.
        public internal(set) var slotSize: Int
        /// The Argon2id parameters every password slot in the file uses.
        public let kdfParameters: Argon2idParameters
        /// The Argon2id salt every password slot in the file uses.
        public let salt: Data

        init(slotSize: Int, kdfParameters: Argon2idParameters, salt: Data) throws {
            guard Self.isValid(slotSize: slotSize), Self.isValid(kdfParameters),
                  salt.count == Self.saltLength
            else {
                throw VaultSlotFileError.malformed
            }
            self.slotSize = slotSize
            self.kdfParameters = kdfParameters
            self.salt = Data(salt)
        }

        /// Reads the header at the start of a file.
        init(parsing bytes: Data) throws {
            guard bytes.count >= Self.magic.count + 2, bytes.prefix(Self.magic.count) == Self.magic else {
                throw VaultSlotFileError.notASlotFile
            }
            let version: UInt16 = bytes.bigEndianInteger(at: 8)
            guard version == Self.currentVersion else {
                throw VaultSlotFileError.unsupportedVersion(version)
            }
            guard bytes.count >= Self.length else {
                throw VaultSlotFileError.malformed
            }
            let slotCount: UInt16 = bytes.bigEndianInteger(at: 10)
            let slotSize: UInt32 = bytes.bigEndianInteger(at: 12)
            let kdf: UInt16 = bytes.bigEndianInteger(at: 16)
            let lanes: UInt8 = bytes.bigEndianInteger(at: 26)
            guard slotCount == VaultSlotFile.slotCount, kdf == Self.argon2idKDF else {
                throw VaultSlotFileError.malformed
            }
            try self.init(
                slotSize: Int(slotSize),
                kdfParameters: Argon2idParameters(
                    memoryKiB: bytes.bigEndianInteger(at: 18),
                    iterations: bytes.bigEndianInteger(at: 22),
                    parallelism: UInt32(lanes),
                ),
                salt: bytes.dropFirst(32).prefix(Self.saltLength),
            )
            // The zero gap and the reserved bytes must be zero. Checking the whole encoding covers them.
            guard encoded() == bytes.prefix(Self.length) else {
                throw VaultSlotFileError.malformed
            }
        }

        /// The header's 128 bytes.
        func encoded() -> Data {
            var data = Data(capacity: Self.length)
            data.append(Self.magic)
            data.appendBigEndianInteger(Self.currentVersion)
            data.appendBigEndianInteger(UInt16(VaultSlotFile.slotCount))
            data.appendBigEndianInteger(UInt32(slotSize))
            data.appendBigEndianInteger(Self.argon2idKDF)
            data.appendBigEndianInteger(kdfParameters.memoryKiB)
            data.appendBigEndianInteger(kdfParameters.iterations)
            data.appendBigEndianInteger(UInt8(kdfParameters.parallelism))
            data.append(Data(count: 5))
            data.append(salt)
            data.append(Data(count: 64))
            return data
        }

        /// The header as the slots authenticate it: with the slot size zeroed, because growth changes it.
        var authenticatedBytes: Data {
            var data = encoded()
            data.replaceBigEndianInteger(at: 12, with: UInt32(0))
            return data
        }

        private static func isValid(slotSize: Int) -> Bool {
            slotSize >= VaultSlotFile.minimumSlotSize && slotSize <= VaultSlotFile.maximumSlotSize
                && slotSize.nonzeroBitCount == 1
        }

        private static func isValid(_ parameters: Argon2idParameters) -> Bool {
            memoryKiBRange.contains(parameters.memoryKiB)
                && passesRange.contains(parameters.iterations)
                && lanesRange.contains(parameters.parallelism)
                && parameters.memoryKiB >= 8 * parameters.parallelism
        }
    }
}

// MARK: - Password key

extension VaultSlotFile.Header {
    /// Derives `K_pw` from the app lock password, with this file's parameters and salt.
    ///
    /// The password is used as its UTF-8 in Unicode's composed form (NFC), so it derives the same key however the
    /// keyboard put its accents together. Setting, trying and changing a password all derive through here, so they
    /// always agree.
    ///
    /// It takes as long as calibration chose, about half a second on the device that created the file, so call it
    /// off the main actor. The key goes straight from the derivation's wiped buffer into a `SymmetricKey`, which is
    /// zeroed when it's released, and the password's bytes are wiped.
    public func passwordKey(for password: String) throws -> VaultSlotRootKey {
        var bytes = Data(password.precomposedStringWithCanonicalMapping.utf8)
        defer { SlotRandom.wipe(&bytes) }
        let deriver = Argon2idKeyDeriver<32>(parameters: kdfParameters)
        let key = try deriver.withKeyBytes(password: bytes, salt: salt) { SymmetricKey(data: $0) }
        return .password(derivedKey: key)
    }
}
