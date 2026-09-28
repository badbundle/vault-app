import CryptoEngine
import Foundation
import FoundationExtensions
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// The slot file fixture: a whole encrypted vault file, with a real vault, a duress vault made from it, and random
/// slots. See `Fixtures/README.md`.
struct SlotFileFixtureTests {
    @Test
    func header_isTheOneTheFileWasMadeWith() throws {
        let stored = try GoldenFixture.data(named: SlotFileFixture.name)

        let file = try SlotFileFixture.file()

        #expect(stored.count == VaultSlotFile.Header.length + SlotFileFixture.storedSlots.count * (1 << 20))
        #expect(file.bytes.count == VaultSlotFile.Header.length + VaultSlotFile.slotCount * (1 << 20))
        #expect(file.bytes.prefix(VaultSlotFile.Header.length) == stored.prefix(VaultSlotFile.Header.length))
        #expect(file.header.slotSize == 1 << 20)
        #expect(file.header.kdfParameters == SlotFileFixture.kdfParameters)
        #expect(file.header.salt.toHexString() == SlotFileFixture.salt)
    }

    @Test(arguments: SlotFileFixture.vaults)
    func password_opensOnlyItsVaultsSlot(vault: SlotFileFixture.Vault) throws {
        let file = try SlotFileFixture.file()
        let key = try file.header.passwordKey(for: vault.password)

        let opened = VaultSlotFile.slotIndices.compactMap { try? file.openSlot($0, with: key) }

        #expect(opened.map(\.index) == [vault.slot])
        #expect(opened.first?.generation == vault.generation)
        #expect(opened.first?.wrappedAt == vault.wrappedAt)
    }

    @Test(arguments: SlotFileFixture.vaults)
    func password_opensExactlyItsVaultsItemsTagsAndSettings(vault: SlotFileFixture.Vault) throws {
        let file = try SlotFileFixture.file()
        let slot = try file.openSlot(vault.slot, with: file.header.passwordKey(for: vault.password))

        let state = try EncryptedVaultPayload.decode(slot: slot, in: file)

        let itemDecoder = PersistedVaultItemDecoder()
        let tagDecoder = PersistedVaultTagDecoder()
        #expect(try state.items.map(itemDecoder.decode(record:)) == vault.items())
        #expect(try state.tags.map(tagDecoder.decode(record:)) == vault.tags)
        #expect(state.vault.settings == vault.settings)
        #expect(state.vault.duressSlots == vault.duressSlots)
    }

    @Test
    func wrongPassword_opensNoSlot() throws {
        let file = try SlotFileFixture.file()
        let key = try file.header.passwordKey(for: SlotFileFixture.wrongPassword)

        let opened = VaultSlotFile.slotIndices.filter { (try? file.openSlot($0, with: key)) != nil }

        #expect(opened.isEmpty)
    }

    /// Both of a slot's boxes authenticate its index, so the stored slots rebuilt into each other's places open
    /// nothing.
    @Test(arguments: SlotFileFixture.vaults)
    func storedSlotsInEachOthersPlaces_openNoSlot(vault: SlotFileFixture.Vault) throws {
        let file = try SlotFileFixture.file(placingStoredSlotsAt: SlotFileFixture.storedSlots.reversed())
        let key = try file.header.passwordKey(for: vault.password)

        let opened = VaultSlotFile.slotIndices.filter { (try? file.openSlot($0, with: key)) != nil }

        #expect(opened.isEmpty)
    }

    /// A password derives from its composed form (NFC), so the duress password opens its vault however the keyboard
    /// put its accent together.
    @Test
    func duressPasswordWithTheAccentDecomposed_opensTheDuressVault() throws {
        let file = try SlotFileFixture.file()
        let decomposed = SlotFileFixture.duress.password.decomposedStringWithCanonicalMapping
        let key = try file.header.passwordKey(for: decomposed)

        let opened = try file.openSlot(SlotFileFixture.duress.slot, with: key)

        // Swift compares strings by canonical equivalence, so compare the bytes a derivation is given.
        #expect(Array(decomposed.utf8) != Array(SlotFileFixture.duress.password.utf8))
        #expect(opened.generation == SlotFileFixture.duress.generation)
    }

    /// A file's Argon2id parameters are chosen once, on the device that makes it, and kept in its header. A device
    /// that would calibrate differently, faster or slower, derives with the header's and opens the vault.
    @Test(arguments: [Duration.milliseconds(3), .seconds(1)])
    func unlock_onADeviceThatCalibratesDifferently_opensTheVault(calibrationRun: Duration) async throws {
        let calibration = try AppLockKeyDerivationCalibrator(timer: FixedDerivationTimer(duration: calibrationRun))
            .calibrate()
        let contents = try SlotFileFixture.file()
        let fileSystem = InMemorySlotFileSystem()
        let file = EncryptedVaultFile(directory: EncryptedVaultFixture.inMemoryDirectory, fileSystem: fileSystem)
        try fileSystem.createFile(at: file.url, contents: contents.bytes)
        let session = VaultStoreSession(target: .locked)
        let service = VaultUnlockService(
            file: file,
            session: session,
            attemptCounter: AppLockPasswordAttemptCounter(
                storage: LoggingAttemptStorage(log: SharedMutex([String]())),
                clock: FakeAppLockClock(),
            ),
            deadlineStore: FakeUnlockDeadlineStore(deadline: calibration.unlockDeadline),
            deviceKeyStore: InMemoryDeviceKeyStore(),
            purgeVaultContents: {},
            clock: ManualUnlockClock(),
            availableMemory: { nil },
            wrapStamper: .inMemory(),
        )

        let result = try await service.unlock(password: SlotFileFixture.real.password)

        #expect(calibration.parameters != contents.header.kdfParameters)
        #expect(result == .unlocked)
        let vault = try await session.exportVault(userDescription: "")
        #expect(try vault.items == SlotFileFixture.real.items())
        #expect(vault.tags == SlotFileFixture.real.tags)
    }
}

// MARK: - Helpers

extension SlotFileFixtureTests {
    /// Times every calibration run as `duration`, as a faster or slower device would.
    private struct FixedDerivationTimer: Argon2idDerivationTiming {
        var duration: Duration

        func timeDerivation(parameters _: Argon2idParameters) throws -> Duration {
            duration
        }
    }
}

// MARK: - Fixture

/// A whole encrypted vault file (`vault-slots.v1`, format version 1, payload version 1) with 1 MiB slots. It holds a
/// real vault, a duress vault made from it, and fourteen slots of random bytes, as a file does after the App Lock
/// Password is set and a duress password added.
///
/// `slot-file-v1-vault-slots.bin` stores the file's header and the two slots that hold the vaults, byte for byte, and
/// `file()` rebuilds the rest: the other fourteen slots are only random bytes, 14 MiB that would tell a test nothing.
///
/// `GoldenFixtureRecorder.recordSlotFile()` made it with the app's own code. The values marked as recorded are what
/// that code chose at random, which the recorder printed; the rest is what it was given.
enum SlotFileFixture {
    static let name = "slot-file-v1-vault-slots.bin"

    /// Cheap, so a derivation takes about a millisecond. The header carries them, as it carries whatever the device
    /// that made a file calibrated. Calibration itself always chooses 64 MiB.
    static let kdfParameters = Argon2idParameters(memoryKiB: 256, iterations: 3, parallelism: 1)
    /// Differs from the real password only in its first letter's case.
    static let wrongPassword = "Correct horse battery staple"

    /// The header's salt, recorded.
    static let salt = "3995d7dd968c0815f618ba1168d78fe53c28691e2553a918e8b7f551bdd8c52a"

    /// The slots the fixture stores after the header, in the order it stores them: the ones that hold a vault,
    /// recorded.
    static let storedSlots = [6, 15]

    /// The whole file, rebuilt from the fixture in the test bundle once, for every test.
    static func file() throws -> VaultSlotFile {
        try rebuiltFile.get()
    }

    private static let rebuiltFile = Result { try file(placingStoredSlotsAt: storedSlots) }

    /// Rebuilds the whole file from the fixture: its header, then each of the sixteen slots at its offset. The stored
    /// slots go at `indices`, in the order they're stored, and every other slot is filled with bytes from a seeded
    /// generator, as random bytes stand in for them.
    static func file(placingStoredSlotsAt indices: [Int]) throws -> VaultSlotFile {
        let stored = try GoldenFixture.data(named: name)
        let header = try VaultSlotFile.Header(parsing: stored)
        let slotSize = header.slotSize
        try #require(stored.count == VaultSlotFile.Header.length + storedSlots.count * slotSize)
        var generator = SeededRandomNumberGenerator(seed: 86)
        var bytes = Data(stored.prefix(VaultSlotFile.Header.length))
        bytes.reserveCapacity(VaultSlotFile.Header.length + VaultSlotFile.slotCount * slotSize)
        for index in VaultSlotFile.slotIndices {
            if let position = indices.firstIndex(of: index) {
                let start = VaultSlotFile.Header.length + position * slotSize
                bytes.append(stored[start ..< start + slotSize])
            } else {
                bytes.append(randomBytes(count: slotSize, using: &generator))
            }
        }
        return try VaultSlotFile(bytes: bytes)
    }

    /// `count` bytes from the generator, 8 at a time. Slot sizes are multiples of 8.
    private static func randomBytes(count: Int, using generator: inout SeededRandomNumberGenerator) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { buffer in
            for offset in stride(from: 0, to: count, by: 8) {
                buffer.storeBytes(of: generator.next(), toByteOffset: offset, as: UInt64.self)
            }
        }
        return data
    }

    /// A vault in the file, and what it holds.
    struct Vault: Sendable, CustomTestStringConvertible {
        var name: String
        var password: String
        var slot: Int
        var wrappedAt: Date
        /// The key box's generation, recorded: a new vault starts at a random one, and every save adds one.
        var generation: UInt64
        /// Where its duress vaults go, recorded.
        var duressSlots: [Int]
        var tags: [VaultItemTag]
        /// Its items, apart from any encrypted item fixtures.
        var plainItems: [VaultItem]
        /// The encrypted item fixtures it holds, after `plainItems`.
        var encryptedItems: [EncryptedItemFixture]
        var settings: VaultBackupSettings

        var testDescription: String {
            name
        }

        /// Every item in the vault, in the order it's stored.
        func items() throws -> [VaultItem] {
            try plainItems + encryptedItems.map { try $0.storedItem() }
        }
    }

    static let vaults = [real, duress]

    /// The real vault, as turning on the App Lock Password creates it from the plain store.
    static let real = Vault(
        name: "real",
        password: "correct horse battery staple",
        slot: 6,
        wrappedAt: Date(timeIntervalSince1970: 1_790_000_000),
        generation: 1_827_597_023,
        duressSlots: [15, 12, 1, 8, 9, 14, 2, 5, 4, 7],
        tags: [personalTag, workTag],
        plainItems: [
            VaultItem(
                metadata: metadata(
                    id: "ED314A19-B48C-430A-B280-6540D860542C",
                    relativeOrder: 0,
                    userDescription: "Personal email",
                    tags: [personalTag.id],
                    color: VaultItemColor(red: 0.9, green: 0.3, blue: 0.1),
                ),
                item: .otpCode(OTPAuthCode(
                    type: .totp(period: 30),
                    data: OTPAuthCodeData(
                        secret: OTPAuthSecret(data: Data("12345678901234567890".utf8), format: .base32),
                        algorithm: .sha1,
                        digits: 6,
                        accountName: "alice@example.com",
                        issuer: "Example Mail",
                    ),
                )),
            ),
            VaultItem(
                metadata: metadata(
                    id: "C0CF4EE1-08AC-480E-AB5C-DE74624F1D5D",
                    relativeOrder: 10,
                    tags: [workTag.id],
                    searchableLevel: .onlyTitle,
                    killphrase: KillphraseDigest(
                        salt: Data(hex: "dfe0a00469c32ac9530ac73c38926134"),
                        digest: Data(hex: "7834f86149f5ff8242d1ea50ae958e08a82fff95fc0e5f912fa050968a9a5c56"),
                    ),
                    showInQuickType: false,
                    previewMode: .titleOnly,
                ),
                item: .otpCode(OTPAuthCode(
                    type: .hotp(counter: 42),
                    data: OTPAuthCodeData(
                        secret: OTPAuthSecret(data: Data("a bank's hotp secret".utf8), format: .base32),
                        algorithm: .sha256,
                        digits: 8,
                        accountName: "alice",
                        issuer: "Example Bank",
                    ),
                )),
            ),
            VaultItem(
                metadata: metadata(
                    id: "4DF9A6D8-E53D-448E-800A-5320F415A9DE",
                    relativeOrder: 20,
                    tags: [personalTag.id, workTag.id],
                    visibility: .onlySearch,
                    searchableLevel: .onlyPassphrase,
                    searchPassphrase: SearchPassphraseDigest(
                        salt: Data(hex: "3e247a12792f79319a6641e8be118bbc"),
                        digest: Data(hex: "3009ed6d6e43794ccaa0a63ce0a054f0c6edd54229d76e88731e3aaa1adad5fd"),
                    ),
                    lockState: .lockedWithNativeSecurity,
                    previewMode: .hidden,
                ),
                item: .secureNote(SecureNote(
                    title: "Travel plans",
                    contents: "# Itinerary\n\n- Fly out on the 3rd\n- Hotel booking **QX-4471**",
                    format: .markdown,
                )),
            ),
        ],
        encryptedItems: [.note, .recoveryPhrase],
        settings: VaultBackupSettings(
            backupPassword: StoredBackupPassword(
                password: DerivedEncryptionKey(
                    key: backupPasswordKey,
                    salt: Data(
                        hex: "420cc450bce0dd58eaafcf436abcfe571d278e71321c282cf7fcaa43e783a9857827299912b26c7fafdf20e6d40121da",
                    ),
                    keyDervier: .backupFastV1,
                ),
                lastSetDate: Date(timeIntervalSince1970: 1_785_000_000),
            ),
            lastBackupEvent: VaultBackupEvent(
                backupDate: Date(timeIntervalSince1970: 1_789_000_000),
                eventDate: Date(timeIntervalSince1970: 1_789_000_060),
                kind: .exportedToAutoBackup(providerID: "icloud-drive"),
                payloadHash: .init(
                    value: Data(hex: "bdf9fc51cad08a94f3323bb1e3249e849438afc5350b47bd5af156d8ceec1f8f"),
                ),
            ),
            autoBackup: AutoBackupConfiguration(
                isEnabled: true,
                retentionDays: .days30,
                providerID: "icloud-drive",
                providerConfigs: ["icloud-drive": Data("a folder bookmark".utf8)],
                lastBackupHash: "bdf9fc51cad08a94f3323bb1e3249e849438afc5350b47bd5af156d8ceec1f8f",
                lastBackupDate: Date(timeIntervalSince1970: 1_789_000_000),
                backupFilenames: ["Vault Backup 2026-09-09 21-46-40.pdf"],
            ),
            pdfUserHint: "The password is in the blue notebook.",
        ),
    )

    /// A duress vault, made from the real vault with the duress password, then given a few items by importing them.
    static let duress = Vault(
        name: "duress",
        // With an accent, composed, so the file pins that a password derives from its composed form.
        password: "caf\u{E9} au lait",
        // The real vault's first duress slot.
        slot: 15,
        wrappedAt: Date(timeIntervalSince1970: 1_790_086_400),
        generation: 912_205_800,
        duressSlots: [12, 1, 8, 9, 14, 2, 5, 4, 7, 3],
        tags: [shoppingTag],
        plainItems: [
            VaultItem(
                metadata: metadata(
                    id: "7B1A2FFA-A3C6-4A49-9433-33F36A5B4B70",
                    relativeOrder: 0,
                    userDescription: "Game account",
                ),
                item: .otpCode(OTPAuthCode(
                    type: .totp(period: 60),
                    data: OTPAuthCodeData(
                        secret: OTPAuthSecret(data: Data("a game's totp secret".utf8), format: .base32),
                        algorithm: .sha512,
                        digits: 7,
                        accountName: "player one",
                        issuer: "Example Games",
                    ),
                )),
            ),
            VaultItem(
                metadata: metadata(
                    id: "5151CA6D-F763-4857-8687-31216F4EFF40",
                    relativeOrder: 10,
                    tags: [shoppingTag.id],
                ),
                item: .secureNote(SecureNote(title: "Groceries", contents: "Milk\nEggs\nBread", format: .plain)),
            ),
        ],
        encryptedItems: [],
        settings: VaultBackupSettings(pdfUserHint: "Spare phone"),
    )

    /// The real vault's backup password, as it keeps it: the key derived from it.
    private static let backupPasswordKey: KeyData<32> = // swiftlint:disable:next force_try
        try! KeyData(data: Data(hex: "83ffec599c07f19bd83b12c0f1014f780bbfefa3f9c1280f18bf0e572101216f"))

    private static let personalTag = VaultItemTag(
        id: Identifier(id: UUID(uuidString: "A8582716-0C09-475A-9295-A3C0F0E67251")!),
        name: "Personal",
        color: VaultItemColor(red: 0.2, green: 0.5, blue: 0.9),
        iconName: "person.fill",
    )

    private static let workTag = VaultItemTag(
        id: Identifier(id: UUID(uuidString: "B349F093-958A-440D-BEA8-E1231E281A5A")!),
        name: "Work",
    )

    private static let shoppingTag = VaultItemTag(
        id: Identifier(id: UUID(uuidString: "9FAE7C17-5D36-4935-B9E2-BCCCDDF738DD")!),
        name: "Shopping",
        color: VaultItemColor(red: 0.1, green: 0.7, blue: 0.3),
        iconName: "cart.fill",
    )

    private static func metadata(
        id: String,
        relativeOrder: UInt64,
        userDescription: String = "",
        tags: Set<Identifier<VaultItemTag>> = [],
        visibility: VaultItemVisibility = .always,
        searchableLevel: VaultItemSearchableLevel = .full,
        searchPassphrase: SearchPassphraseDigest? = nil,
        killphrase: KillphraseDigest? = nil,
        lockState: VaultItemLockState = .notLocked,
        color: VaultItemColor? = nil,
        showInQuickType: Bool = true,
        previewMode: NotePreviewMode = .titleAndFirstLine,
    ) -> VaultItem.Metadata {
        VaultItem.Metadata(
            id: Identifier(id: UUID(uuidString: id)!),
            created: Date(timeIntervalSince1970: 1_760_000_000 + TimeInterval(relativeOrder)),
            updated: Date(timeIntervalSince1970: 1_770_000_000 + TimeInterval(relativeOrder)),
            relativeOrder: relativeOrder,
            userDescription: userDescription,
            tags: tags,
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphrase: searchPassphrase,
            killphrase: killphrase,
            lockState: lockState,
            color: color,
            showInQuickType: showInQuickType,
            previewMode: previewMode,
        )
    }
}
