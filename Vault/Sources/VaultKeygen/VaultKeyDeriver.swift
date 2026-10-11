import CryptoEngine
import Foundation
import FoundationExtensions

/// A `KeyDeriver` that can actually be used in the context of the Vault app.
/// It contains a resilient `signature`, such that we can lookup the exact
/// algorithm and all parameters when we decrypt.
///
/// Things should only be made into an `VaultKeyDeriver` if they are deemed
/// to be good enough for encryption. This helps to prevent accidental errors like
/// using some random `KeyDeriver` at the application level.
public struct VaultKeyDeriver: KeyDeriver {
    /// The resilient signature that identifies this key deriver.
    ///
    /// Using the signature, this allows us to lookup the algorithm that was used
    /// during the key generation.
    public let signature: Signature

    private let deriver: any KeyDeriver<KeyData<32>>
    /// For a derivation that carries on from another one's key, how it does (`continueDerivation(from:)`).
    private let continuation: Continuation?

    public init(deriver: any KeyDeriver<KeyData<32>>, signature: Signature) {
        self.init(deriver: deriver, signature: signature, continuation: nil)
    }

    private init(deriver: any KeyDeriver<KeyData<32>>, signature: Signature, continuation: Continuation?) {
        self.deriver = deriver
        self.signature = signature
        self.continuation = continuation
    }

    public func key(password: Data, salt: Data) throws -> KeyData<32> {
        try deriver.key(password: password, salt: salt)
    }

    public var uniqueAlgorithmIdentifier: String {
        deriver.uniqueAlgorithmIdentifier
    }
}

extension VaultKeyDeriver: Equatable, Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.signature == rhs.signature
    }

    public func hash(into hasher: inout Swift.Hasher) {
        hasher.combine(signature)
    }
}

extension VaultKeyDeriver {
    /// Resilient signature that is used to identify the algorithm that was used for a given keygen,
    /// so a given key can be recreated.
    public enum Signature: String, Equatable, Codable, Identifiable, CaseIterable, Sendable {
        case testing = "vault.keygen.testing"
        case failing = "vault.keygen.failing"
        case backupFastV1 = "vault.keygen.backup.fast.v1"
        case backupSecureV1 = "vault.keygen.backup.secure.v1"
        case itemFastV1 = "vault.keygen.item.fast.v1"
        case itemSecureV1 = "vault.keygen.item.secure.v1"
        case backupFastV2 = "vault.keygen.backup.fast.v2"
        case backupSecureV2 = "vault.keygen.backup.secure.v2"
        case backupFastV1ThenV2 = "vault.keygen.backup.fast.v1-then-v2"
        case backupSecureV1ThenV2 = "vault.keygen.backup.secure.v1-then-v2"
        case itemFastV2 = "vault.keygen.item.fast.v2"
        case itemSecureV2 = "vault.keygen.item.secure.v2"

        public var id: String {
            rawValue
        }

        public var userVisibleDescription: String {
            switch self {
            case .testing: "Vault Testing"
            case .failing: "Vault Failing"
            case .backupFastV1: "Vault Backup (Fast, v1)"
            case .backupSecureV1: "Vault Backup (Secure, v1)"
            case .itemFastV1: "Vault Item (Fast, v1)"
            case .itemSecureV1: "Vault Item (Secure, v1)"
            case .backupFastV2: "Vault Backup (Fast, v2)"
            case .backupSecureV2: "Vault Backup (Secure, v2)"
            case .backupFastV1ThenV2: "Vault Backup (Fast, v1 then v2)"
            case .backupSecureV1ThenV2: "Vault Backup (Secure, v1 then v2)"
            case .itemFastV2: "Vault Item (Fast, v2)"
            case .itemSecureV2: "Vault Item (Secure, v2)"
            }
        }

        /// The signature `string` names.
        ///
        /// - Throws: `MissingKeyDeriverError` if it names none this version of Vault knows, as for a key made by a
        ///   newer version.
        public init(tryFromString string: String) throws(MissingKeyDeriverError) {
            if let value = Self(rawValue: string) {
                self = value
            } else {
                throw MissingKeyDeriverError()
            }
        }

        /// The derivation an item encrypted with this one moves to, or `nil` if Vault has none stronger for it.
        ///
        /// The next time the item opens in the app, it's encrypted again with a key derived this way from the
        /// password just entered (`EncryptedItemDetailViewModel`). A fast derivation moves to the next fast one, as
        /// it's only ever made by debug builds.
        public var itemUpgrade: Self? {
            switch self {
            case .itemFastV1: .itemFastV2
            case .itemSecureV1: .itemSecureV2
            case .itemFastV2, .itemSecureV2: nil
            case .testing, .failing: nil
            case .backupFastV1, .backupSecureV1, .backupFastV2, .backupSecureV2, .backupFastV1ThenV2,
                 .backupSecureV1ThenV2: nil
            }
        }

        /// The derivation a stored backup password's key moves to, or `nil` if Vault has none stronger for it.
        ///
        /// Only the key is stored, never the password, so the new derivation carries on from the stored key
        /// (`VaultKeyDeriver.continueDerivation(from:)`), and the next time the app loads it, the key is replaced
        /// with the result. Restoring a backup made with the new key derives the old way from the password, then
        /// carries on. A fast derivation moves to the next fast one, as it's only ever made by debug builds.
        public var storedBackupKeyUpgrade: Self? {
            switch self {
            case .backupFastV1: .backupFastV1ThenV2
            case .backupSecureV1: .backupSecureV1ThenV2
            case .backupFastV2, .backupSecureV2, .backupFastV1ThenV2, .backupSecureV1ThenV2: nil
            case .testing, .failing: nil
            case .itemFastV1, .itemSecureV1, .itemFastV2, .itemSecureV2: nil
            }
        }
    }
}

// MARK: - Derviers

extension VaultKeyDeriver {
    /// A key was made with a derivation this version of Vault doesn't know: one a newer version added, as far as
    /// Vault can tell. So it says to update Vault.
    public struct MissingKeyDeriverError: Error, LocalizedError {
        public var errorDescription: String? {
            "Needs a Newer Version of Vault"
        }

        public var failureReason: String? {
            "This was made by a newer version of Vault. Update Vault, then try again."
        }
    }

    /// `continueDerivation(from:)` was given a key this derivation doesn't carry on from.
    public struct NotAContinuationError: Error {}

    /// How a derivation carries on from another one's key.
    private struct Continuation: Sendable {
        /// The derivation whose key it carries on from.
        var from: Signature
        /// Derives this derivation's key from that key and its salt.
        var stage: any KeyDeriver<KeyData<32>>
    }

    /// This derivation's key from a key made by the one it carries on from, without the password: how a stored
    /// backup key moves to a stronger derivation (`Signature.storedBackupKeyUpgrade`).
    ///
    /// The salt stays the same, so a backup made with either key carries the one salt, and this derivation recreates
    /// the same key from the password and that salt. It takes as long as the stronger stage, so run it off the main
    /// actor.
    ///
    /// - Throws: `NotAContinuationError` if this derivation doesn't carry on from `key`'s.
    public func continueDerivation(from key: DerivedEncryptionKey) throws -> DerivedEncryptionKey {
        guard let continuation, continuation.from == key.keyDervier else { throw NotAContinuationError() }
        let continued = try continuation.stage.key(password: key.key.data, salt: key.salt)
        return DerivedEncryptionKey(key: continued, salt: key.salt, keyDervier: signature)
    }

    /// A derivation that carries on from the key `first` makes, with Argon2id and `parameters`.
    ///
    /// The Argon2id stage's password is `first`'s key, and its salt is `signature`'s ID in UTF-8 followed by the
    /// salt `first` used (`LabelledSaltKeyDeriver`), so the key needs only the one salt, and the two stages never
    /// derive with the same salt.
    private static func continuing(
        _ first: VaultKeyDeriver,
        withArgon2id parameters: Argon2idParameters,
        signature: Signature,
    ) -> VaultKeyDeriver {
        let stage = LabelledSaltKeyDeriver(
            label: signature.rawValue,
            deriver: Argon2idKeyDeriver<32>(parameters: parameters),
        )
        return VaultKeyDeriver(
            deriver: CombinationKeyDeriver<32>(derivers: [first, stage]),
            signature: signature,
            continuation: Continuation(from: first.signature, stage: stage),
        )
    }

    public static func lookup(signature: VaultKeyDeriver.Signature) -> VaultKeyDeriver {
        switch signature {
        case .testing: .testing
        case .failing: .failing
        case .backupFastV1: .Backup.Fast.v1
        case .backupSecureV1: .Backup.Secure.v1
        case .itemFastV1: .Item.Fast.v1
        case .itemSecureV1: .Item.Secure.v1
        case .backupFastV2: .Backup.Fast.v2
        case .backupSecureV2: .Backup.Secure.v2
        case .backupFastV1ThenV2: .Backup.Fast.v1ThenV2
        case .backupSecureV1ThenV2: .Backup.Secure.v1ThenV2
        case .itemFastV2: .Item.Fast.v2
        case .itemSecureV2: .Item.Secure.v2
        }
    }

    /// A key deriver that's really fast, just for testing.
    public static let testing: VaultKeyDeriver = {
        let deriver = HKDFKeyDeriver<32>(parameters: .init(variant: .sha3_sha512))
        return VaultKeyDeriver(
            deriver: deriver,
            signature: .testing,
        )
    }()

    public static let failing: VaultKeyDeriver = .init(
        deriver: FailingKeyDeriver(), signature: .failing,
    )

    /// Keyderivers that are used for backups.
    public enum Backup {
        /// Fast backup key derivers.
        public enum Fast {
            /// V1 fast key deriver for backups.
            ///
            /// It's fast to run and to bruteforce (especially for a weak password), but not trivial.
            /// It still uses a combination of key derivation functions for increased security.
            ///
            /// This should be used in places where security is not required or for testing.
            public static let v1: VaultKeyDeriver = {
                var derivers = [any KeyDeriver<KeyData<32>>]()
                derivers.append(PBKDF2KeyDeriver<32>(
                    parameters: .init(
                        iterations: 2000,
                        variant: .sha384,
                    ),
                ))
                derivers.append(HKDFKeyDeriver<32>(
                    parameters: .init(variant: .sha3_sha512),
                ))
                derivers.append(ScryptKeyDeriver<32>(
                    parameters: .init(
                        costFactor: 1 << 6,
                        blockSizeFactor: 4,
                        parallelizationFactor: 1,
                    ),
                ))
                return VaultKeyDeriver(
                    deriver: CombinationKeyDeriver(derivers: derivers),
                    signature: .backupFastV1,
                )
            }()

            /// V2 fast key deriver for backups: Argon2id in the shape of `Secure.v2`, four lanes and all, with a
            /// fraction of its memory and passes, so it takes milliseconds.
            ///
            /// Debug builds use it, and the golden fixtures, so they exercise the same code as `Secure.v2`.
            public static let v2 = VaultKeyDeriver(
                deriver: Argon2idKeyDeriver<32>(parameters: v2Parameters),
                signature: .backupFastV2,
            )

            /// `v1`, carried on with `v2`'s Argon2id: the fast counterpart of `Secure.v1ThenV2`, for a backup
            /// password a debug build set with `v1`.
            public static let v1ThenV2 = continuing(v1, withArgon2id: v2Parameters, signature: .backupFastV1ThenV2)

            /// 8 MiB, 2 passes, 4 lanes.
            public static let v2Parameters = Argon2idParameters(memoryKiB: 8 * 1024, iterations: 2, parallelism: 4)
        }

        public enum Secure {
            /// V1 secure key deriver for backups.
            ///
            /// This takes a significant amount of time to compute on general computing hardware, increasing
            /// the cost of a bruteforce attack significantly. It's still feasible for a user that knows a
            /// password (should take no more than a minute to compute on a standard iPhone for example).
            ///
            /// This uses a chain of different KDF algorithms to increase the cost of a bruteforce attack
            /// in the event that an offline encrypted vault is obtained by a bad actor.
            ///
            /// This is intended to be the initial production version of the KDF for the Vault app.
            public static let v1: VaultKeyDeriver = {
                var derivers = [any KeyDeriver<KeyData<32>>]()
                // Initial PBKDF2 for strong password hashing
                derivers.append(PBKDF2KeyDeriver<32>(
                    parameters: .init(
                        iterations: 5_452_351,
                        variant: .sha384,
                    ),
                ))
                derivers.append(HKDFKeyDeriver<32>(
                    parameters: .init(variant: .sha3_sha512),
                ))
                // Scrypt for memory-hard key derivation
                // Requires ~250MB of memory at peak with these current parameters.
                // This should be fine for most iOS devices to perform locally.
                derivers.append(ScryptKeyDeriver<32>(
                    parameters: .init(
                        costFactor: 1 << 18,
                        blockSizeFactor: 8,
                        parallelizationFactor: 1,
                    ),
                ))
                return VaultKeyDeriver(
                    deriver: CombinationKeyDeriver<32>(derivers: derivers),
                    signature: .backupSecureV1,
                )
            }()

            /// V2 secure key deriver for backups: Argon2id over 512 MiB, with 32 passes and 4 lanes.
            ///
            /// Every backup password set or changed from v2 on derives with it. It takes about 7 seconds on an M5 Max
            /// with its lanes run one after another, and about 14 on an iPhone 11, and needs 512 MiB, so it only ever
            /// runs in the app, never in an extension (see `docs/on-device-encryption.md`).
            public static let v2 = VaultKeyDeriver(
                deriver: Argon2idKeyDeriver<32>(parameters: v2Parameters),
                signature: .backupSecureV2,
            )

            /// `v1`, carried on with `v2`'s Argon2id, for a backup password set before v2.
            ///
            /// Only the key a password derives is stored, never the password, so a stored `v1` key can't be derived
            /// again with `v2`. Instead it's carried on: the stored key is the password of `v2`'s Argon2id, so
            /// guessing a password costs `v1` and `v2` together (`continueDerivation(from:)`). Restoring a backup
            /// made with it runs `v1` from the password, then `v2`.
            public static let v1ThenV2 = continuing(
                v1,
                withArgon2id: v2Parameters,
                signature: .backupSecureV1ThenV2,
            )

            /// 512 MiB, 32 passes, 4 lanes.
            public static let v2Parameters = Argon2idParameters(
                memoryKiB: 512 * 1024,
                iterations: 32,
                parallelism: 4,
            )
        }
    }

    /// Keyderivers that are used for individual items within a vault.
    public enum Item {
        public enum Fast {
            public static let v1: VaultKeyDeriver = {
                var derivers = [any KeyDeriver<KeyData<32>>]()
                derivers.append(ScryptKeyDeriver<32>(
                    parameters: .init(
                        costFactor: 1 << 6,
                        blockSizeFactor: 4,
                        parallelizationFactor: 1,
                    ),
                ))
                derivers.append(PBKDF2KeyDeriver<32>(
                    parameters: .init(
                        iterations: 1001,
                        variant: .sha384,
                    ),
                ))
                return VaultKeyDeriver(
                    deriver: CombinationKeyDeriver<32>(derivers: derivers),
                    signature: .itemFastV1,
                )
            }()

            /// V2 fast key deriver for items: Argon2id in the shape of `Secure.v2`, with a fraction of its memory
            /// and passes. Debug builds and the golden fixtures use it.
            public static let v2 = VaultKeyDeriver(
                deriver: Argon2idKeyDeriver<32>(parameters: v2Parameters),
                signature: .itemFastV2,
            )

            /// 4 MiB, 2 passes, 4 lanes.
            public static let v2Parameters = Argon2idParameters(memoryKiB: 4 * 1024, iterations: 2, parallelism: 4)
        }

        public enum Secure {
            public static let v1: VaultKeyDeriver = {
                var derivers = [any KeyDeriver<KeyData<32>>]()
                derivers.append(ScryptKeyDeriver<32>(
                    parameters: .init(
                        costFactor: 1 << 8,
                        blockSizeFactor: 4,
                        parallelizationFactor: 1,
                    ),
                ))
                derivers.append(PBKDF2KeyDeriver<32>(
                    parameters: .init(
                        iterations: 372_002,
                        variant: .sha384,
                    ),
                ))
                return VaultKeyDeriver(
                    deriver: CombinationKeyDeriver<32>(derivers: derivers),
                    signature: .itemSecureV1,
                )
            }()

            /// V2 secure key deriver for items: Argon2id over 256 MiB, with 4 passes and 4 lanes.
            ///
            /// Every item password set or changed from v2 on derives with it, and an item encrypted with `v1` moves
            /// to it the next time it's opened (`Signature.itemUpgrade`). It needs 256 MiB, so it only ever runs in
            /// the app, never in an extension.
            public static let v2 = VaultKeyDeriver(
                deriver: Argon2idKeyDeriver<32>(parameters: v2Parameters),
                signature: .itemSecureV2,
            )

            /// 256 MiB, 4 passes, 4 lanes.
            public static let v2Parameters = Argon2idParameters(
                memoryKiB: 256 * 1024,
                iterations: 4,
                parallelism: 4,
            )
        }
    }
}

/// Derives with `deriver`, with its salt behind a fixed label: the label in UTF-8, then the salt it's given.
///
/// For a stage that carries on from another derivation made with the same salt, so the two never derive with the
/// same salt (`VaultKeyDeriver.continueDerivation(from:)`).
struct LabelledSaltKeyDeriver: KeyDeriver {
    let label: String
    let deriver: any KeyDeriver<KeyData<32>>

    func key(password: Data, salt: Data) throws -> KeyData<32> {
        try deriver.key(password: password, salt: Data(label.utf8) + salt)
    }

    var uniqueAlgorithmIdentifier: String {
        "LABELLED_SALT<label=\(label);\(deriver.uniqueAlgorithmIdentifier)>"
    }
}
