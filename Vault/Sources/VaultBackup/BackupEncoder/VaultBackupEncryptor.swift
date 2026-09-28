import CryptoEngine
import Foundation
import FoundationExtensions
import VaultCore
import VaultKeygen

/// Used to create a full, encrypted backup of a vault for export.
public final class VaultBackupEncryptor {
    private let clock: any EpochClock
    private let key: VaultKey
    private let keygenSalt: Data
    private let keygenSignature: String
    private let paddingMode: PaddingMode

    public enum PaddingMode: Equatable {
        case none
        case fixed(data: Data)
        /// A random amount, which blurs a backup's size without hiding it.
        case random
        /// As much as brings what's encrypted to just under a fixed size: `minimum` bytes, or the first of twice that,
        /// four times and so on that it fits (VAULT-75). Backups of small vaults and of larger ones up to `minimum` are
        /// then the same size, and a larger backup shows only roughly how large it is. The random amount of padding
        /// is inside the encryption, so nothing readable without the password shows how much of it there is.
        case toFixedSize(minimum: Int)
    }

    /// How close under its fixed size a backup padded with `PaddingMode.toFixedSize(minimum:)` ends up: the most
    /// bytes it can fall short by.
    static let fixedSizeTolerance = 16

    public init(
        clock: any EpochClock,
        key: VaultKey,
        keygenSalt: Data,
        keygenSignature: String,
        paddingMode: PaddingMode = .random,
    ) {
        self.clock = clock
        self.key = key
        self.keygenSalt = keygenSalt
        self.keygenSignature = keygenSignature
        self.paddingMode = paddingMode
    }

    /// Encodes and encrypts a vault providing a payload.
    ///
    /// - Parameters:
    ///   - killphraseKeys: The HMAC keys the items' killphrase digests can have been made with. Left out of the
    ///     backup when empty.
    ///   - searchPassphraseKeys: The HMAC keys the items' search passphrase digests can have been made with. Left out
    ///     of the backup when empty.
    public func encryptBackupPayload(
        items: [VaultBackupItem],
        tags: [VaultBackupTag],
        userDescription: String,
        killphraseKeys: [Data] = [],
        searchPassphraseKeys: [Data] = [],
    ) throws -> EncryptedVault {
        let payload = VaultBackupPayload(
            version: "1.0.0",
            created: clock.currentDate,
            userDescription: userDescription,
            tags: tags,
            items: items,
            killphraseKeys: killphraseKeys.isEmpty ? nil : killphraseKeys,
            searchPassphraseKeys: searchPassphraseKeys.isEmpty ? nil : searchPassphraseKeys,
            obfuscationPadding: makePadding(itemsCount: items.count),
        )
        let intermediateEncoding = switch paddingMode {
        case let .toFixedSize(minimum):
            try Self.encodeFillingFixedSize(payload, minimum: minimum)
        case .none, .fixed, .random:
            try IntermediateEncodedVaultEncoder().encode(vaultBackup: payload)
        }
        let encryptor = VaultEncryptor(key: key, keygenSalt: keygenSalt, keygenSignature: keygenSignature)
        return try encryptor.encrypt(encodedVault: intermediateEncoding)
    }

    private func makePadding(itemsCount: Int) -> Data {
        switch paddingMode {
        case .none, .toFixedSize: Data()
        case let .fixed(data): data
        case .random: Data.random(count: randomBytesToGenerate(itemsCount: itemsCount))
        }
    }

    /// Encodes `payload` with as much random padding as brings the compressed encoding, which is what's encrypted, to
    /// within `fixedSizeTolerance` bytes under the smallest fixed size it fits (`fixedSize(fitting:minimum:)`).
    ///
    /// The padding is always a prefix of the same random bytes, and only its length is searched for. Compression can't
    /// shrink random bytes, so each byte of padding adds about a byte, and one byte more or less changes the encoding
    /// by a few bytes at most. So between a length that fits and one that doesn't, there's always a length that lands
    /// within the tolerance. (Fresh random bytes of the same length compress to lengths tens of bytes apart, more than
    /// the tolerance, which is why each try doesn't draw new ones.)
    ///
    /// It keeps the longest length it knows fits and the shortest it knows doesn't, and tries the length between them
    /// that the two suggest. The first try, from the estimate alone, usually overshoots a little, and the second, from
    /// the two, lands within the tolerance, or now and then the third. It keeps the largest encoding that fits, in case
    /// it doesn't get within the tolerance.
    static func encodeFillingFixedSize(
        _ payload: VaultBackupPayload,
        minimum: Int,
    ) throws -> IntermediateEncodedVault {
        let encoder = IntermediateEncodedVaultEncoder()
        var payload = payload
        payload.obfuscationPadding = Data()
        let unpadded = try encoder.encode(vaultBackup: payload)
        let size = fixedSize(fitting: unpadded.data.count, minimum: minimum)
        let aim = size - fixedSizeTolerance / 2
        // Enough for any length the search tries: this many random bytes alone encode to more than `size`.
        let randomBytes = Data.random(count: size)
        var best = unpadded
        var fits = (paddingLength: 0, length: unpadded.data.count)
        var doesNotFit: (paddingLength: Int, length: Int)?
        for _ in 0 ..< 32 {
            guard size - best.data.count > fixedSizeTolerance else { break }
            let paddingLength: Int
            if let doesNotFit {
                guard doesNotFit.paddingLength - fits.paddingLength > 1 else { break }
                // Where the aim falls on the line between the two.
                let paddingPerByte = Double(doesNotFit.paddingLength - fits.paddingLength)
                    / Double(doesNotFit.length - fits.length)
                let estimate = fits.paddingLength + Int(Double(aim - fits.length) * paddingPerByte)
                paddingLength = min(max(estimate, fits.paddingLength + 1), doesNotFit.paddingLength - 1)
            } else {
                // Each byte of padding adds about a byte.
                guard fits.paddingLength < randomBytes.count else { break }
                let estimate = fits.paddingLength + aim - fits.length
                paddingLength = min(max(estimate, fits.paddingLength + 1), randomBytes.count)
            }
            payload.obfuscationPadding = randomBytes.prefix(paddingLength)
            let padded = try encoder.encode(vaultBackup: payload)
            if padded.data.count <= size {
                fits = (paddingLength, padded.data.count)
                if padded.data.count > best.data.count {
                    best = padded
                }
            } else {
                doesNotFit = (paddingLength, padded.data.count)
            }
        }
        return best
    }

    /// The fixed size a compressed encoding of `length` bytes is padded to: `minimum`, or the first of twice that,
    /// four times and so on that holds it.
    static func fixedSize(fitting length: Int, minimum: Int) -> Int {
        var size = minimum
        while size < length {
            size *= 2
        }
        return size
    }

    private func randomBytesToGenerate(itemsCount: Int) -> Int {
        if itemsCount == 0 {
            Int.random(in: 400 ..< 2700)
        } else if itemsCount < 10 {
            Int.random(in: 300 ..< 3300)
        } else if itemsCount < 40 {
            Int.random(in: 600 ..< 4500)
        } else {
            Int.random(in: 200 ..< 6000)
        }
    }
}
