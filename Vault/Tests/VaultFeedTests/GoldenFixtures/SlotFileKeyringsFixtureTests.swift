import CryptoEngine
import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

/// The slot file fixture with payload version 2, where each vault keeps its own killphrase and search passphrase
/// keyrings in its payload (VAULT-127): a real vault, a duress vault made from it, and random slots. See
/// `Fixtures/README.md`.
struct SlotFileKeyringsFixtureTests {
    @Test
    func header_isTheOneTheFileWasMadeWith() throws {
        let stored = try GoldenFixture.data(named: SlotFileKeyringsFixture.name)

        let file = try SlotFileKeyringsFixture.file()

        #expect(stored.count == VaultSlotFile.Header.length + SlotFileKeyringsFixture.storedSlots.count * (1 << 20))
        #expect(file.header.slotSize == 1 << 20)
        #expect(file.header.kdfParameters == SlotFileKeyringsFixture.kdfParameters)
        #expect(file.header.salt.toHexString() == SlotFileKeyringsFixture.salt)
    }

    @Test(arguments: SlotFileKeyringsFixture.vaults)
    func password_opensOnlyItsVaultsSlot(vault: SlotFileKeyringsFixture.Vault) throws {
        let file = try SlotFileKeyringsFixture.file()
        let key = try file.header.passwordKey(for: vault.password)

        let opened = VaultSlotFile.slotIndices.compactMap { try? file.openSlot($0, with: key) }

        #expect(opened.map(\.index) == [vault.slot])
        #expect(opened.first?.generation == vault.generation)
        #expect(opened.first?.wrappedAt == vault.wrappedAt)
    }

    /// Each payload is version 2, and holds exactly its vault's items and its own keyrings.
    @Test(arguments: SlotFileKeyringsFixture.vaults)
    func password_opensExactlyItsVaultsItemsAndKeyrings(vault: SlotFileKeyringsFixture.Vault) throws {
        let file = try SlotFileKeyringsFixture.file()
        let slot = try file.openSlot(vault.slot, with: file.header.passwordKey(for: vault.password))

        let state = try EncryptedVaultPayload.decode(slot: slot, in: file)

        let itemDecoder = PersistedVaultItemDecoder()
        #expect(try file.openPayload(of: slot).version == 2)
        #expect(try state.items.map(itemDecoder.decode(record:)) == vault.items)
        #expect(state.tags.isEmpty)
        #expect(state.vault.keyrings == vault.keyrings)
        #expect(state.vault.duressSlots == vault.duressSlots)
        #expect(state.vault.settings == VaultBackupSettings())
    }

    /// Every phrase in a vault matches with that vault's keyrings, the ones it was digested with, and with no other
    /// vault's: a duress vault's keys check none of the real vault's phrases, nor the other way round.
    @Test(arguments: SlotFileKeyringsFixture.vaults)
    func eachVaultsPhrases_matchWithItsOwnKeyringsOnly(vault: SlotFileKeyringsFixture.Vault) throws {
        let other = try #require(SlotFileKeyringsFixture.vaults.first { $0.name != vault.name })

        for item in vault.items {
            if let killphrase = item.metadata.killphrase, let phrase = vault.killphrases[item.id] {
                #expect(Self.killphraseDigester(vault.keyrings).matches(
                    query: phrase,
                    salt: killphrase.salt,
                    digest: killphrase.digest,
                ))
                #expect(!Self.killphraseDigester(other.keyrings).matches(
                    query: phrase,
                    salt: killphrase.salt,
                    digest: killphrase.digest,
                ))
            }
            if let searchPassphrase = item.metadata.searchPassphrase, let phrase = vault.searchPassphrases[item.id] {
                #expect(Self.searchPassphraseDigester(vault.keyrings).matches(
                    query: phrase,
                    salt: searchPassphrase.salt,
                    digest: searchPassphrase.digest,
                ))
                #expect(!Self.searchPassphraseDigester(other.keyrings).matches(
                    query: phrase,
                    salt: searchPassphrase.salt,
                    digest: searchPassphrase.digest,
                ))
            }
        }
        #expect(vault.killphrases.isNotEmpty)
    }

    /// No key is on both vaults' keyrings.
    @Test
    func vaults_shareNoKey() {
        func keys(_ vault: SlotFileKeyringsFixture.Vault) -> Set<KeyData<32>> {
            Set(vault.keyrings.killphrase.allKeys + vault.keyrings.searchPassphrase.allKeys)
        }

        #expect(keys(SlotFileKeyringsFixture.real).isDisjoint(with: keys(SlotFileKeyringsFixture.duress)))
    }

    /// Unlocked on a device whose keychain has none of its keys, as on another Mac the file was moved to with
    /// Migration Assistant, the vault's phrases work: its keys came with it. Nothing is read from the keychain or
    /// written to the file.
    @MainActor
    @Test
    func unlock_onADeviceWithNoneOfItsKeys_theVaultsPhrasesWork() async throws {
        let contents = try SlotFileKeyringsFixture.file()
        let fileSystem = InMemorySlotFileSystem()
        let file = EncryptedVaultFile(directory: EncryptedVaultFixture.inMemoryDirectory, fileSystem: fileSystem)
        try fileSystem.createFile(at: file.url, contents: contents.bytes)
        let real = SlotFileKeyringsFixture.real
        let store = try EncryptedVaultStore(
            file: file,
            contents: contents,
            slot: contents.openSlot(real.slot, with: contents.header.passwordKey(for: real.password)),
        )
        let session = VaultStoreSession(target: .unlocked(store))
        let keychain = InMemorySecureStorage()
        let keyrings = OpenVaultPhraseKeyrings(session: session, device: DevicePhraseKeyrings(secureStorage: keychain))
        let dataModel = anyVaultDataModel(
            vaultStore: session,
            vaultTagStore: session,
            vaultImporter: session,
            vaultDeleter: session,
            vaultKillphraseDeleter: session,
            killphraseKeyStore: keyrings.killphraseKeys,
            searchPassphraseKeyStore: keyrings.searchPassphraseKeys,
        )
        await dataModel.openVaultDidChange()
        let opened = try #require(try fileSystem.contents(of: file.url))

        dataModel.itemsSearchQuery = SlotFileKeyringsFixture.searchPassphrase
        await dataModel.reloadItems()
        let found = dataModel.items.map(\.id)

        #expect(found == [SlotFileKeyringsFixture.hiddenNoteID])
        #expect(opened == contents.bytes)
        #expect(try await DevicePhraseKeyrings(secureStorage: keychain).killphrase.loadAllKeys().isEmpty)
        #expect(await !keychain.contains(key: VaultIdentifiers.SecureStorageKey.killphraseKey.rawValue))
    }

    private static func killphraseDigester(_ keyrings: VaultPhraseKeyrings) -> KillphraseDigester {
        KillphraseDigester(key: keyrings.killphrase.ownKey, keysFromBackups: keyrings.killphrase.keysFromBackups)
    }

    private static func searchPassphraseDigester(_ keyrings: VaultPhraseKeyrings) -> SearchPassphraseDigester {
        SearchPassphraseDigester(
            key: keyrings.searchPassphrase.ownKey,
            keysFromBackups: keyrings.searchPassphrase.keysFromBackups,
        )
    }
}

// MARK: - Fixture

/// A whole encrypted vault file (`vault-slots.v1`, format version 1, payload version 2) with 1 MiB slots. It holds a
/// real vault, a duress vault made from it, and fourteen slots of random bytes, as a file does once vaults keep their
/// own keyrings (VAULT-127).
///
/// `slot-file-v1-payload-v2-vault-slots.bin` stores the file's header and the two slots that hold the vaults, as
/// `SlotFileFixture` does, and `file()` rebuilds the rest.
///
/// `GoldenFixtureRecorder.recordSlotFileWithKeyrings()` made it with the app's own code. The values marked as recorded
/// are what that code chose at random, which the recorder printed; the rest is what it was given.
enum SlotFileKeyringsFixture {
    static let name = "slot-file-v1-payload-v2-vault-slots.bin"

    /// As `SlotFileFixture`'s: a derivation takes about a millisecond.
    static let kdfParameters = SlotFileFixture.kdfParameters

    /// The header's salt, recorded.
    static let salt = "d98c3194d140ff6cdb4487d4ffb7e06de2c94cb0965de272cde8c21b2add68e2"

    /// The slots that hold a vault, in the order the fixture stores them, recorded.
    static let storedSlots = [9, 11]

    static let killphrase = "kill me"
    static let searchPassphrase = "find me"
    /// A killphrase whose digest was made with a key a restored backup brought, before the file was made.
    static let restoredKillphrase = "kill me too"
    static let duressKillphrase = "duress kill"

    static let hiddenNoteID = Identifier<VaultItem>(id: UUID(uuidString: "2B9E6C1D-7F3A-4E58-9C0B-61D4A8F2E7B3")!)

    /// The whole file, rebuilt from the fixture in the test bundle once, for every test.
    static func file() throws -> VaultSlotFile {
        try rebuiltFile.get()
    }

    private static let rebuiltFile = Result {
        try SlotFileFixture.file(named: name, storedSlots: storedSlots, placingStoredSlotsAt: storedSlots)
    }

    /// A vault in the file, and what it holds.
    struct Vault: Sendable, CustomTestStringConvertible {
        var name: String
        var password: String
        var slot: Int
        var wrappedAt: Date
        /// The key box's generation, recorded.
        var generation: UInt64
        /// Where its duress vaults go, recorded.
        var duressSlots: [Int]
        var items: [VaultItem]
        var keyrings: VaultPhraseKeyrings
        /// Each killphrase, by the item it deletes.
        var killphrases: [Identifier<VaultItem>: String]
        /// Each search passphrase, by the item it shows.
        var searchPassphrases: [Identifier<VaultItem>: String] = [:]

        var testDescription: String {
            name
        }
    }

    static let vaults = [real, duress]

    /// The real vault, as turning on the App Lock Password makes it from a plain store whose keyrings were these: its
    /// own keys, and a killphrase key a restored backup brought.
    static let real = Vault(
        name: "real",
        password: "correct horse battery staple",
        slot: 9,
        wrappedAt: Date(timeIntervalSince1970: 1_791_000_000),
        generation: 373_078_189,
        duressSlots: [11, 6, 12, 13, 2, 0, 4, 15, 8, 14],
        items: realItems,
        keyrings: VaultPhraseKeyrings(
            killphrase: .init(ownKey: .repeating(byte: 0xE1), keysFromBackups: [.repeating(byte: 0xE3)]),
            searchPassphrase: .init(ownKey: .repeating(byte: 0xE2)),
        ),
        killphrases: [realItems[0].id: killphrase, realItems[2].id: restoredKillphrase],
        searchPassphrases: [hiddenNoteID: searchPassphrase],
    )

    /// A duress vault, made from the real vault with the duress password, with keyrings of its own that its store
    /// gave it, then given a code with a killphrase digested with them, by importing it.
    static let duress = Vault(
        name: "duress",
        password: "caf\u{E9} au lait",
        // The real vault's first duress slot.
        slot: 11,
        wrappedAt: Date(timeIntervalSince1970: 1_791_086_400),
        generation: 3_099_705_946,
        duressSlots: [6, 12, 13, 2, 0, 4, 15, 8, 14, 7],
        items: [duressItem(killphrase: KillphraseDigest(
            // `duressKillphrase`, with the duress vault's own killphrase key, recorded.
            salt: Data(hex: "c69e3bee4c55c7f3e57046efab7baeb8"),
            digest: Data(hex: "770673b3361b0c9d8cc21dded2cc3a7cb245db4510380df2403fd3ccff98e347"),
        ))],
        // Recorded.
        keyrings: VaultPhraseKeyrings(
            killphrase: .init(ownKey: key(hex: "7b2960e2661ab0038d8fd45b4db06d0714cff8b97f9067a92db18c947d617513")),
            searchPassphrase: .init(
                ownKey: key(hex: "d583b9510ab57cf48b2d6dc9d0a24bc565fce2695e39bf7106f96daa0812cfb8"),
            ),
        ),
        killphrases: [duressItemID: duressKillphrase],
    )

    private static let realItems = [
        VaultItem(
            metadata: metadata(
                id: "8E2F4A61-3C7B-4D95-A0E8-5B1C9F2D6A47",
                relativeOrder: 0,
                userDescription: "Personal email",
                // `killphrase`, with the killphrase keyring's own key.
                killphrase: KillphraseDigest(
                    salt: Data(hex: "1f2e3d4c5b6a79881f2e3d4c5b6a7988"),
                    digest: Data(hex: "5279299b5e20b90fedd9be2117884416804d232ed82eb14c06191e9ce5b86b4d"),
                ),
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
                id: hiddenNoteID.id.uuidString,
                relativeOrder: 10,
                visibility: .onlySearch,
                searchableLevel: .onlyPassphrase,
                // `searchPassphrase`, with the search passphrase keyring's own key.
                searchPassphrase: SearchPassphraseDigest(
                    salt: Data(hex: "a1b2c3d4e5f60718293a4b5c6d7e8f90"),
                    digest: Data(hex: "0dcf72814869a0bb4e83f614d5550046f7097ff952a34cc2e454877bbe78d4e3"),
                ),
            ),
            item: .secureNote(SecureNote(title: "Travel plans", contents: "Fly out on the 3rd", format: .plain)),
        ),
        VaultItem(
            metadata: metadata(
                id: "D47C1E92-5A3F-4B86-8E0D-2F6B9C1A7E35",
                relativeOrder: 20,
                // `restoredKillphrase`, with the key a restored backup brought.
                killphrase: KillphraseDigest(
                    salt: Data(hex: "0a1b2c3d4e5f60718293a4b5c6d7e8f9"),
                    digest: Data(hex: "1656df1566a639311450b25cdaeaba5156f580c55d0441ff4d4b4883b03acf05"),
                ),
            ),
            item: .otpCode(OTPAuthCode(
                type: .hotp(counter: 7),
                data: OTPAuthCodeData(
                    secret: OTPAuthSecret(data: Data("a bank's hotp secret".utf8), format: .base32),
                    algorithm: .sha256,
                    digits: 8,
                    accountName: "alice",
                    issuer: "Example Bank",
                ),
            )),
        ),
    ]

    static let duressItemID = Identifier<VaultItem>(id: UUID(uuidString: "6F0A9D3E-2B8C-4C71-B5E4-93A1D7F02C68")!)

    /// The duress vault's code, with its killphrase's digest.
    static func duressItem(killphrase: KillphraseDigest) -> VaultItem {
        VaultItem(
            metadata: metadata(
                id: duressItemID.id.uuidString,
                relativeOrder: 0,
                userDescription: "Game account",
                killphrase: killphrase,
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
        )
    }

    private static func key(hex: String) -> KeyData<32> {
        // swiftlint:disable:next force_try
        try! KeyData(data: Data(hex: hex))
    }

    private static func metadata(
        id: String,
        relativeOrder: UInt64,
        userDescription: String = "",
        visibility: VaultItemVisibility = .always,
        searchableLevel: VaultItemSearchableLevel = .full,
        searchPassphrase: SearchPassphraseDigest? = nil,
        killphrase: KillphraseDigest? = nil,
    ) -> VaultItem.Metadata {
        VaultItem.Metadata(
            id: Identifier(id: UUID(uuidString: id)!),
            created: Date(timeIntervalSince1970: 1_780_000_000 + TimeInterval(relativeOrder)),
            updated: Date(timeIntervalSince1970: 1_781_000_000 + TimeInterval(relativeOrder)),
            relativeOrder: relativeOrder,
            userDescription: userDescription,
            tags: [],
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphrase: searchPassphrase,
            killphrase: killphrase,
            lockState: .notLocked,
            color: nil,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )
    }
}
