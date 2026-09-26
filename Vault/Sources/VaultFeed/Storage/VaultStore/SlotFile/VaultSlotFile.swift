import CryptoEngine
import CryptoKit
import Foundation

/// The encrypted vault file, `vault-slots.v1`: a 128-byte plaintext header, then 16 slots of equal size.
///
/// Every slot is either a vault or random bytes, and the two look the same. A vault's slot holds:
///
/// - **The slot nonce** (32 bytes). It salts the slot's wrap key and is part of the slot's associated data.
/// - **The key box** (84 bytes). The vault's data key, the body's length, a generation counter and when the key was
///   wrapped, sealed with AES-256-GCM under the slot's wrap key.
/// - **The body box**. The compressed payload, zero-filled to the end of the slot, sealed with AES-256-GCM under
///   the data key. After another slot has grown the file, it's followed by random fill.
///
/// Both boxes authenticate the header, the slot's index and its nonce. So a changed salt or KDF parameter, a slot
/// moved to another index, or a slot moved to another file, fails to open. The slot size is the one header field
/// left out, because growing the file changes it for slots the app can't open.
///
/// This type only transforms bytes. Reading, locking and replacing the file belong to the encrypted store, and trying
/// every slot within the unlock deadline to the unlock service. See "On-disk format" in
/// `docs/on-device-encryption.md`.
public struct VaultSlotFile: Equatable, Sendable {
    /// The number of slots, fixed for the format.
    public static let slotCount = 16
    /// The slot size of a new file. It holds about 3,500 typical items once compressed.
    public static let minimumSlotSize = 1 << 20
    /// The largest slot size growth goes to: 4 MiB, which holds about 14,000 typical items and makes a 64 MiB file.
    /// A payload that doesn't fit is refused.
    ///
    /// It bounds memory as well as the file: a save holds the whole file twice at its peak, the new file and the copy
    /// read back to verify it, which is 128 MiB at this size.
    public static let maximumSlotSize = 1 << 22

    /// The indices of the slots.
    public static var slotIndices: Range<Int> {
        0 ..< slotCount
    }

    static let slotNonceLength = 32
    static let keyBoxLength = 84
    /// Where the body box starts in a slot.
    static let bodyOffset = slotNonceLength + keyBoxLength
    /// What AES-GCM adds to a plaintext in a combined box: the 12-byte nonce and the 16-byte tag.
    static let sealOverhead = 12 + 16
    /// The body's own header: payload version (4), compression (4) and compressed length (8).
    static let bodyHeaderLength = 16

    /// The largest compressed payload a slot of this size holds.
    static func payloadCapacity(slotSize: Int) -> Int {
        slotSize - bodyOffset - sealOverhead - bodyHeaderLength
    }

    /// The smallest slot size, from `slotSize` upwards, that holds a compressed payload of this length, or `nil` if
    /// even the maximum doesn't.
    static func slotSize(fittingCompressedLength length: Int, from slotSize: Int) -> Int? {
        var size = slotSize
        while payloadCapacity(slotSize: size) < length {
            size *= 2
            guard size <= maximumSlotSize else { return nil }
        }
        return size
    }

    /// The header, as it is at the start of `bytes`.
    public private(set) var header: Header
    /// The whole file, as it's written to disk.
    public private(set) var bytes: Data

    /// A new file with every slot random. No key opens anything in it until a vault is created in a slot.
    ///
    /// - Parameter kdfParameters: The Argon2id parameters every password slot in the file uses, for the life of
    ///   the file.
    public init(kdfParameters: Argon2idParameters) throws {
        let header = try Header(
            slotSize: Self.minimumSlotSize,
            kdfParameters: kdfParameters,
            salt: SlotRandom.bytes(count: Header.saltLength),
        )
        var bytes = header.encoded()
        bytes.append(SlotRandom.bytes(count: Self.slotCount * header.slotSize))
        self.header = header
        self.bytes = bytes
    }

    /// Reads a file from its bytes, checking the header and the length. Opening slots is separate.
    ///
    /// - Throws: `VaultSlotFileError.notASlotFile`, `.unsupportedVersion(_:)` or `.malformed`.
    public init(bytes: Data) throws {
        let bytes = bytes.startIndex == 0 ? bytes : Data(bytes)
        let header = try Header(parsing: bytes)
        guard bytes.count == Header.length + Self.slotCount * header.slotSize else {
            throw VaultSlotFileError.malformed
        }
        self.header = header
        self.bytes = bytes
    }
}

// MARK: - Opened slots

extension VaultSlotFile {
    /// A slot whose key box has been opened: which slot it is, what its key box records, and the keys to read and
    /// rewrite it.
    ///
    /// It holds the slot's wrap key and data key, so keep it only while the vault is unlocked.
    public struct OpenedSlot: Sendable {
        /// The slot's index in the file.
        public let index: Int
        /// Goes up by one on every write to the slot: creating it, saving and rewrapping.
        public let generation: UInt64
        /// When the data key was last wrapped, in milliseconds since 1970: when the vault was created, or last
        /// rewrapped. Saves don't change it.
        let wrappedAtMilliseconds: UInt64
        let slotNonce: Data
        let wrapKey: SymmetricKey
        let dataKey: SymmetricKey
        /// The length of the body box, from the start of the body to its tag.
        let bodyLength: Int

        /// When the data key was last wrapped: when the vault was created, or last rewrapped. Saves don't change it.
        /// When a password opens more than one slot, the most recently wrapped wins.
        public var wrappedAt: Date {
            Date(timeIntervalSince1970: TimeInterval(wrappedAtMilliseconds) / 1000)
        }
    }
}

// MARK: - Opening

extension VaultSlotFile {
    /// Opens slot `index`'s key box with a root key: `K_pw` from the app lock password, or the device key.
    ///
    /// - Throws: `VaultSlotFileError.slotDidNotOpen` for every failure. A wrong key, a slot with no vault in it
    ///   and a tampered slot look the same.
    public func openSlot(_ index: Int, with rootKey: VaultSlotRootKey) throws -> OpenedSlot {
        precondition(Self.slotIndices.contains(index), "Slot index out of range")
        let nonce = slotNonce(index)
        return try openKeyBox(index, slotNonce: nonce, wrapKey: rootKey.wrapKey(slotNonce: nonce))
    }

    /// Opens the key box of a slot opened earlier, perhaps in an older copy of the file, with the wrap key kept
    /// from then.
    ///
    /// A save uses it on the file it's about to replace, to see whether anyone else has written the slot since.
    ///
    /// - Throws: `VaultSlotFileError.slotDidNotOpen` if the slot has been rewrapped or replaced since.
    public func reopen(_ slot: OpenedSlot) throws -> OpenedSlot {
        try openKeyBox(slot.index, slotNonce: slotNonce(slot.index), wrapKey: slot.wrapKey)
    }

    /// Opens and decompresses the payload of a slot opened in this file.
    ///
    /// - Throws: `VaultSlotFileError.bodyDidNotOpen` if the body is damaged or has been tampered with, or
    ///   `.unsupportedCompression(_:)` if it was compressed in a way this app doesn't know.
    public func openPayload(of slot: OpenedSlot) throws -> VaultSlotPayload {
        let bodyStart = slotRange(slot.index).lowerBound + Self.bodyOffset
        guard slot.bodyLength <= header.slotSize - Self.bodyOffset else {
            throw VaultSlotFileError.bodyDidNotOpen
        }
        var plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: bytes[bodyStart ..< bodyStart + slot.bodyLength])
            plaintext = try AES.GCM.open(
                box,
                using: slot.dataKey,
                authenticating: associatedData(slot: slot.index, slotNonce: slotNonce(slot.index)),
            )
        } catch {
            throw VaultSlotFileError.bodyDidNotOpen
        }
        defer { SlotRandom.wipe(&plaintext) }

        guard plaintext.count >= Self.bodyHeaderLength else { throw VaultSlotFileError.bodyDidNotOpen }
        let version: UInt32 = plaintext.bigEndianInteger(at: 0)
        let compressionID: UInt32 = plaintext.bigEndianInteger(at: 4)
        let compressedLength: UInt64 = plaintext.bigEndianInteger(at: 8)
        guard compressedLength <= UInt64(plaintext.count - Self.bodyHeaderLength) else {
            throw VaultSlotFileError.bodyDidNotOpen
        }
        guard let compression = VaultSlotCompression(rawValue: compressionID) else {
            throw VaultSlotFileError.unsupportedCompression(compressionID)
        }
        let data: Data
        do {
            // Scoped so the slice is gone before the plaintext is wiped: a live slice would make the wipe copy.
            let compressed = plaintext.dropFirst(Self.bodyHeaderLength).prefix(Int(compressedLength))
            data = try compression.decompress(compressed)
        }
        return VaultSlotPayload(version: version, data: data)
    }

    private func openKeyBox(_ index: Int, slotNonce: Data, wrapKey: SymmetricKey) throws -> OpenedSlot {
        let keyBoxStart = slotRange(index).lowerBound + Self.slotNonceLength
        var plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: bytes[keyBoxStart ..< keyBoxStart + Self.keyBoxLength])
            plaintext = try AES.GCM.open(
                box,
                using: wrapKey,
                authenticating: associatedData(slot: index, slotNonce: slotNonce),
            )
        } catch {
            throw VaultSlotFileError.slotDidNotOpen
        }
        defer { SlotRandom.wipe(&plaintext) }

        guard plaintext.count == KeyBox.plaintextLength else { throw VaultSlotFileError.slotDidNotOpen }
        let bodyLength: UInt64 = plaintext.bigEndianInteger(at: KeyBox.dataKeyLength)
        let bodyLengths = UInt64(Self.sealOverhead + Self.bodyHeaderLength) ...
            UInt64(header.slotSize - Self.bodyOffset)
        guard bodyLengths.contains(bodyLength) else { throw VaultSlotFileError.slotDidNotOpen }
        return OpenedSlot(
            index: index,
            generation: plaintext.bigEndianInteger(at: KeyBox.dataKeyLength + 8),
            wrappedAtMilliseconds: plaintext.bigEndianInteger(at: KeyBox.dataKeyLength + 16),
            slotNonce: slotNonce,
            wrapKey: wrapKey,
            dataKey: SymmetricKey(data: plaintext.prefix(KeyBox.dataKeyLength)),
            bodyLength: Int(bodyLength),
        )
    }
}

// MARK: - Writing

extension VaultSlotFile {
    /// Creates a vault in slot `index`, replacing whatever was there, which can't be recovered afterwards.
    ///
    /// The slot gets a new nonce and a new random data key, wrapped by `rootKey`, at generation 1. If the payload
    /// doesn't fit, every slot grows first, as for `seal(_:in:compression:)`.
    ///
    /// - Parameter wrappedAt: Now. It breaks ties when a password opens more than one slot.
    /// - Throws: `VaultSlotFileError.payloadTooLarge` if the payload doesn't fit the largest slot size. The file is
    ///   unchanged when it throws.
    /// - Returns: The slot as written.
    @discardableResult
    public mutating func createVault(
        inSlot index: Int,
        rootKey: VaultSlotRootKey,
        payload: VaultSlotPayload,
        wrappedAt: Date,
        compression: VaultSlotCompression = .lzfse,
    ) throws -> OpenedSlot {
        precondition(Self.slotIndices.contains(index), "Slot index out of range")
        var compressed = try compression.compress(payload.data)
        defer { SlotRandom.wipe(&compressed) }
        let slotSize = try slotSize(fittingCompressedLength: compressed.count)
        let slotNonce = SlotRandom.bytes(count: Self.slotNonceLength)
        let slot = OpenedSlot(
            index: index,
            generation: 1,
            wrappedAtMilliseconds: Self.milliseconds(since1970: wrappedAt),
            slotNonce: slotNonce,
            wrapKey: rootKey.wrapKey(slotNonce: slotNonce),
            dataKey: SymmetricKey(size: .bits256),
            bodyLength: slotSize - Self.bodyOffset,
        )
        let body = try sealedBody(of: slot, version: payload.version, compression: compression, compressed: compressed)
        let keyBox = try sealedKeyBox(of: slot)
        grow(to: slotSize)
        place(slot, keyBox: keyBox, body: body)
        return slot
    }

    /// Replaces the payload of an opened slot, at the next generation.
    ///
    /// The body is resealed with a fresh nonce to fill the slot, and the key box is resealed to match. If the
    /// payload doesn't fit, every slot grows first: this one is written at the new size, and every other slot is
    /// copied byte for byte with random fill appended, so it still opens.
    ///
    /// - Throws: `VaultSlotFileError.slotChanged` if the slot has been written since `slot` was opened, or
    ///   `.payloadTooLarge` if the payload doesn't fit the largest slot size. The file is unchanged when it throws.
    /// - Returns: The slot as written.
    @discardableResult
    public mutating func seal(
        _ payload: VaultSlotPayload,
        in slot: OpenedSlot,
        compression: VaultSlotCompression = .lzfse,
    ) throws -> OpenedSlot {
        let current = try requireUnchanged(slot)
        var compressed = try compression.compress(payload.data)
        defer { SlotRandom.wipe(&compressed) }
        let slotSize = try slotSize(fittingCompressedLength: compressed.count)
        let sealed = OpenedSlot(
            index: current.index,
            generation: current.generation + 1,
            wrappedAtMilliseconds: current.wrappedAtMilliseconds,
            slotNonce: current.slotNonce,
            wrapKey: current.wrapKey,
            dataKey: current.dataKey,
            bodyLength: slotSize - Self.bodyOffset,
        )
        let body = try sealedBody(
            of: sealed,
            version: payload.version,
            compression: compression,
            compressed: compressed,
        )
        let keyBox = try sealedKeyBox(of: sealed)
        grow(to: slotSize)
        place(sealed, keyBox: keyBox, body: body)
        return sealed
    }

    /// Wraps an opened slot's data key under another root key, at the next generation: for a password change, or
    /// switching between the password and the device key.
    ///
    /// Only the key box changes. The slot nonce and the body stay as they are, and the old root key no longer
    /// opens the slot.
    ///
    /// - Parameter wrappedAt: Now. It breaks ties when a password opens more than one slot.
    /// - Throws: `VaultSlotFileError.slotChanged` if the slot has been written since `slot` was opened. The file is
    ///   unchanged when it throws.
    /// - Returns: The slot as written.
    @discardableResult
    public mutating func rewrap(
        _ slot: OpenedSlot,
        with rootKey: VaultSlotRootKey,
        wrappedAt: Date,
    ) throws -> OpenedSlot {
        let current = try requireUnchanged(slot)
        let rewrapped = OpenedSlot(
            index: current.index,
            generation: current.generation + 1,
            wrappedAtMilliseconds: Self.milliseconds(since1970: wrappedAt),
            slotNonce: current.slotNonce,
            wrapKey: rootKey.wrapKey(slotNonce: current.slotNonce),
            dataKey: current.dataKey,
            bodyLength: current.bodyLength,
        )
        let keyBox = try sealedKeyBox(of: rewrapped)
        place(rewrapped, keyBox: keyBox, body: nil)
        return rewrapped
    }

    /// Throws `slotChanged` unless the slot's key box still opens with the slot's wrap key, at the same
    /// generation. Writing over a slot someone else has written since would lose their write, and resealing a key
    /// box over a body sealed with another nonce or data key would break the slot.
    ///
    /// - Returns: The slot as the file's key box records it now.
    private func requireUnchanged(_ slot: OpenedSlot) throws -> OpenedSlot {
        guard let current = try? reopen(slot), current.generation == slot.generation else {
            throw VaultSlotFileError.slotChanged
        }
        return current
    }

    /// The slot size the file needs for a compressed payload of this length: the current one, or a larger one.
    private func slotSize(fittingCompressedLength length: Int) throws -> Int {
        guard let slotSize = Self.slotSize(fittingCompressedLength: length, from: header.slotSize) else {
            throw VaultSlotFileError.payloadTooLarge
        }
        return slotSize
    }

    /// Grows every slot to `newSlotSize`, if it's larger: each slot is copied to its new place, with random fill
    /// after it.
    private mutating func grow(to newSlotSize: Int) {
        guard newSlotSize > header.slotSize else { return }
        var newHeader = header
        newHeader.slotSize = newSlotSize
        var newBytes = newHeader.encoded()
        newBytes.reserveCapacity(Header.length + Self.slotCount * newSlotSize)
        for index in Self.slotIndices {
            newBytes.append(bytes[slotRange(index)])
            newBytes.append(SlotRandom.bytes(count: newSlotSize - header.slotSize))
        }
        header = newHeader
        bytes = newBytes
    }

    /// The body box: `payload version (4) ‖ compression (4) ‖ compressed length (8) ‖ payload ‖ zero fill`, sealed
    /// with the data key to the slot's body length.
    private func sealedBody(
        of slot: OpenedSlot,
        version: UInt32,
        compression: VaultSlotCompression,
        compressed: Data,
    ) throws -> Data {
        var plaintext = Data(count: slot.bodyLength - Self.sealOverhead)
        defer { SlotRandom.wipe(&plaintext) }
        plaintext.replaceBigEndianInteger(at: 0, with: version)
        plaintext.replaceBigEndianInteger(at: 4, with: compression.rawValue)
        plaintext.replaceBigEndianInteger(at: 8, with: UInt64(compressed.count))
        plaintext.replaceSubrange(
            Self.bodyHeaderLength ..< Self.bodyHeaderLength + compressed.count,
            with: compressed,
        )
        return try Self.seal(
            plaintext,
            using: slot.dataKey,
            authenticating: associatedData(slot: slot.index, slotNonce: slot.slotNonce),
        )
    }

    /// The key box: `K_i (32) ‖ body length (8) ‖ generation (8) ‖ wrapped-at ms (8)`, sealed with the wrap key.
    private func sealedKeyBox(of slot: OpenedSlot) throws -> Data {
        var plaintext = Data(capacity: KeyBox.plaintextLength)
        defer { SlotRandom.wipe(&plaintext) }
        slot.dataKey.withUnsafeBytes { plaintext.append(contentsOf: $0) }
        plaintext.appendBigEndianInteger(UInt64(slot.bodyLength))
        plaintext.appendBigEndianInteger(slot.generation)
        plaintext.appendBigEndianInteger(slot.wrappedAtMilliseconds)
        return try Self.seal(
            plaintext,
            using: slot.wrapKey,
            authenticating: associatedData(slot: slot.index, slotNonce: slot.slotNonce),
        )
    }

    /// Writes the slot nonce, the key box and, if given, the body into the slot.
    private mutating func place(_ slot: OpenedSlot, keyBox: Data, body: Data?) {
        let slotStart = slotRange(slot.index).lowerBound
        bytes.replaceSubrange(slotStart ..< slotStart + Self.slotNonceLength, with: slot.slotNonce)
        bytes.replaceSubrange(slotStart + Self.slotNonceLength ..< slotStart + Self.bodyOffset, with: keyBox)
        if let body {
            bytes.replaceSubrange(slotStart + Self.bodyOffset ..< slotStart + Self.bodyOffset + body.count, with: body)
        }
    }

    private static func seal(_ plaintext: Data, using key: SymmetricKey, authenticating aad: Data) throws -> Data {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(), authenticating: aad)
        } catch {
            throw VaultSlotFileError.sealFailed
        }
        guard let combined = box.combined else { throw VaultSlotFileError.sealFailed }
        return combined
    }

    private static func milliseconds(since1970 date: Date) -> UInt64 {
        UInt64(max(0, (date.timeIntervalSince1970 * 1000).rounded(.down)))
    }
}

// MARK: - Layout

extension VaultSlotFile {
    /// The key box's plaintext: `K_i (32) ‖ body length (8) ‖ generation (8) ‖ wrapped-at ms (8)`.
    enum KeyBox {
        static let dataKeyLength = 32
        static let plaintextLength = dataKeyLength + 8 + 8 + 8
    }

    /// The byte range of slot `index` in `bytes`.
    func slotRange(_ index: Int) -> Range<Int> {
        let start = Header.length + index * header.slotSize
        return start ..< start + header.slotSize
    }

    func slotNonce(_ index: Int) -> Data {
        let start = slotRange(index).lowerBound
        return Data(bytes[start ..< start + Self.slotNonceLength])
    }

    /// `header ‖ i ‖ slot nonce`, authenticated by both of a slot's boxes. The header's slot size is zeroed,
    /// because growth changes it for every slot, and the index is two bytes, big-endian.
    func associatedData(slot index: Int, slotNonce: Data) -> Data {
        var data = header.authenticatedBytes
        data.appendBigEndianInteger(UInt16(index))
        data.append(slotNonce)
        return data
    }
}
