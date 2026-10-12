import CryptoKit
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// Where the open vault's killphrase and search passphrase keyrings are (VAULT-127): an encrypted vault's own in its
/// payload, so they move with the vault file, and the plain store's, and a vault's while the device key opens it, in
/// the keychain. A vault made before vaults kept their own takes a copy of the keychain's, and no key is ever lost.
struct OpenVaultPhraseKeyringsTests {
    /// This device's keyrings, as an earlier version left them: every vault's phrases were digested with them.
    private static let deviceKillphraseKey = KeyData<32>.repeating(byte: 0xD1)
    private static let deviceSearchPassphraseKey = KeyData<32>.repeating(byte: 0xD2)
    private static let restoredKillphraseKey = KeyData<32>.repeating(byte: 0xB1)

    // MARK: - The plain store

    @Test
    func plainStore_keepsItsKeyringsInTheKeychain() async throws {
        let sut = try await Harness.plain()

        let own = try await sut.keyrings.ownKey(.killphrase)
        try await sut.keyrings.addKeysFromBackup([Self.restoredKillphraseKey], to: .killphrase)

        #expect(try await sut.device.killphrase.loadOrCreateOwnKey() == own)
        #expect(try await sut.device.killphrase.loadKeysFromBackups() == [Self.restoredKillphraseKey])
        #expect(try await sut.keyrings.keysFromBackups(.killphrase) == [Self.restoredKillphraseKey])
    }
}

// MARK: - An encrypted vault with keyrings of its own

extension OpenVaultPhraseKeyringsTests {
    /// It uses its own, from its payload, and never reads or writes the keychain's.
    @Test
    func encryptedVault_usesItsOwnKeyringsAndNeverTheKeychains() async throws {
        let keyrings = VaultPhraseKeyrings.random()
        let sut = try await Harness.encrypted(keyrings: keyrings, deviceKeys: true)

        #expect(try await sut.keyrings.ownKey(.killphrase) == keyrings.killphrase.ownKey)
        #expect(try await sut.keyrings.ownKey(.searchPassphrase) == keyrings.searchPassphrase.ownKey)
        #expect(try await sut.keyrings.keysFromBackups(.killphrase) == [])
        #expect(try sut.fixture.savedState().vault.keyrings == keyrings)
        #expect(try await sut.device.killphrase.loadAllKeys() == [Self.deviceKillphraseKey, Self.restoredKillphraseKey])
    }

    /// A backup's keys go into the vault's payload, saved to its slot, and the keychain is left as it was.
    @Test
    func encryptedVault_addKeysFromBackup_savesThemInItsPayload() async throws {
        let keyrings = VaultPhraseKeyrings.random()
        let sut = try await Harness.encrypted(keyrings: keyrings, deviceKeys: true)

        try await sut.keyrings.addKeysFromBackup(
            [Self.restoredKillphraseKey, keyrings.killphrase.ownKey],
            to: .killphrase,
        )

        var expected = keyrings
        expected.killphrase.keysFromBackups = [Self.restoredKillphraseKey]
        #expect(try sut.fixture.savedState().vault.keyrings == expected)
        #expect(try await sut.keyrings.keysFromBackups(.killphrase) == [Self.restoredKillphraseKey])
        #expect(try await sut.device.killphrase.loadAllKeys() == [Self.deviceKillphraseKey, Self.restoredKillphraseKey])
    }

    @Test
    func lockedVault_hasNoKeyrings() async throws {
        let sut = try await Harness.encrypted(keyrings: .random())
        await sut.session.lock()

        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.keyrings.ownKey(.killphrase)
        }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.keyrings.addKeysFromBackup([Self.restoredKillphraseKey], to: .killphrase)
        }
    }
}

// MARK: - A vault from before vaults kept their own

extension OpenVaultPhraseKeyringsTests {
    /// It takes a copy of the keychain's, with a new key of its own for each kind, saves it in its payload before any
    /// of it is used, and leaves the keychain's for any other vault made then that hasn't opened yet.
    @Test
    func vaultWithoutKeyrings_takesACopyOfTheKeychainsWithANewKeyOfItsOwn() async throws {
        let sut = try await Harness.encrypted(keyrings: nil, deviceKeys: true)

        let own = try await sut.keyrings.ownKey(.killphrase)

        let saved = try #require(try sut.fixture.savedState().vault.keyrings)
        #expect(own == saved.killphrase.ownKey)
        #expect(own != Self.deviceKillphraseKey)
        #expect(saved.killphrase.keysFromBackups == [Self.deviceKillphraseKey, Self.restoredKillphraseKey])
        #expect(saved.searchPassphrase.keysFromBackups == [Self.deviceSearchPassphraseKey])
        #expect(saved.searchPassphrase.ownKey != Self.deviceSearchPassphraseKey)
        #expect(try await sut.keyrings.keysFromBackups(.killphrase) == saved.killphrase.keysFromBackups)
        #expect(try await sut.device.killphrase.loadAllKeys() == [Self.deviceKillphraseKey, Self.restoredKillphraseKey])
        #expect(try await sut.device.searchPassphrase.loadAllKeys() == [Self.deviceSearchPassphraseKey])
    }

    /// Once it has its own, it takes nothing again: the file isn't written, and the keys stay as they were.
    @Test
    func vaultWithoutKeyrings_takingACopyAgain_changesNothing() async throws {
        let sut = try await Harness.encrypted(keyrings: nil, deviceKeys: true)
        let own = try await sut.keyrings.ownKey(.killphrase)
        let saved = try sut.fixture.bytes()

        #expect(try await sut.keyrings.ownKey(.killphrase) == own)
        #expect(try await sut.keyrings.ownKey(.searchPassphrase) != own)
        #expect(try sut.fixture.bytes() == saved)
    }

    /// If the copy can't be saved, the vault keeps using the keychain's, which are all still there, and takes its
    /// copy the next time its keys are read.
    @Test
    func vaultWithoutKeyrings_copyThatCantBeSaved_usesTheKeychainsAndTriesAgainLater() async throws {
        let sut = try await Harness.encrypted(keyrings: nil, deviceKeys: true)
        sut.fileSystem.inject(.failEvery(stepNamed: "create temp", fromStep: 0))

        let ownWhileFailing = try await sut.keyrings.ownKey(.killphrase)
        let keysWhileFailing = try await sut.keyrings.keysFromBackups(.killphrase)

        #expect(ownWhileFailing == Self.deviceKillphraseKey)
        #expect(keysWhileFailing == [Self.restoredKillphraseKey])
        #expect(try sut.fixture.savedState().vault.keyrings == nil)
        #expect(try await sut.device.killphrase.loadAllKeys() == [Self.deviceKillphraseKey, Self.restoredKillphraseKey])

        sut.fileSystem.inject(nil)
        let own = try await sut.keyrings.ownKey(.killphrase)

        let saved = try #require(try sut.fixture.savedState().vault.keyrings)
        #expect(own == saved.killphrase.ownKey)
        #expect(saved.killphrase.keysFromBackups == [Self.deviceKillphraseKey, Self.restoredKillphraseKey])
    }

    /// Without keys in the keychain, as on another Mac a vault reached with Migration Assistant, it starts keyrings of
    /// its own.
    @Test
    func vaultWithoutKeyrings_andNoneInTheKeychain_startsItsOwn() async throws {
        let sut = try await Harness.encrypted(keyrings: nil)

        let own = try await sut.keyrings.ownKey(.searchPassphrase)

        let saved = try #require(try sut.fixture.savedState().vault.keyrings)
        #expect(saved.searchPassphrase == .init(ownKey: own))
        #expect(saved.killphrase.keysFromBackups.isEmpty)
        #expect(try await sut.device.searchPassphrase.loadAllKeys().isEmpty)
    }

    /// A backup restored into it goes into the copy it takes, in the same save.
    @Test
    func vaultWithoutKeyrings_addKeysFromBackup_takesItsCopyWithThem() async throws {
        let sut = try await Harness.encrypted(keyrings: nil, deviceKeys: true)
        let fromBackup = KeyData<32>.repeating(byte: 0xB2)

        try await sut.keyrings.addKeysFromBackup([fromBackup], to: .searchPassphrase)

        let saved = try #require(try sut.fixture.savedState().vault.keyrings)
        #expect(saved.searchPassphrase.keysFromBackups == [Self.deviceSearchPassphraseKey, fromBackup])
        #expect(saved.killphrase.keysFromBackups == [Self.deviceKillphraseKey, Self.restoredKillphraseKey])
        #expect(try await sut.device.searchPassphrase.loadAllKeys() == [Self.deviceSearchPassphraseKey])
    }

    /// Each vault made then takes its own copy, with a key of its own that no other vault has, and neither touches
    /// the other's slot.
    @Test
    func vaultsWithoutKeyrings_eachTakeACopyWithAKeyOfTheirOwn() async throws {
        let sut = try await Harness.encrypted(keyrings: nil, deviceKeys: true)
        let other = try await sut.fixture.addingVault(inSlot: (sut.fixture.slotIndex + 5) % VaultSlotFile.slotCount)
        let otherStore = try await other.openStore()
        let realOwn = try await sut.keyrings.ownKey(.killphrase)
        let realSlotBytes = try Self.slotBytes(sut.fixture)

        await sut.session.switchTo(.unlocked(otherStore))
        let otherOwn = try await sut.keyrings.ownKey(.killphrase)

        #expect(otherOwn != realOwn)
        let otherKeyrings = try #require(try other.savedState().vault.keyrings)
        #expect(!otherKeyrings.killphrase.allKeys.contains(realOwn))
        #expect(otherKeyrings.killphrase.keysFromBackups == [Self.deviceKillphraseKey, Self.restoredKillphraseKey])
        #expect(try Self.slotBytes(sut.fixture) == realSlotBytes)
    }

    /// A killphrase and a search passphrase set before the vault kept its own keys still work once it has, through
    /// the data model, as the app has it: the keys they were digested with are among the vault's.
    @MainActor
    @Test
    func vaultWithoutKeyrings_phrasesSetBeforeItKeptItsOwn_stillWork() async throws {
        let armed = anySecureNote(title: "armed").wrapInAnyVaultItem(
            killphrase: KillphraseDigester(key: Self.deviceKillphraseKey).makeDigest(phrase: "kill me"),
        )
        let hidden = anySecureNote(title: "hidden").wrapInAnyVaultItem(
            visibility: .onlySearch,
            searchableLevel: .onlyPassphrase,
            searchPassphrase: SearchPassphraseDigester(key: Self.deviceSearchPassphraseKey)
                .makeDigest(phrase: "find me"),
        )
        let kept = anySecureNote(title: "kept").wrapInAnyVaultItem()
        let state = try EncryptedVaultStoreTests.state(items: [armed, hidden, kept])
        let sut = try await Harness.encrypted(keyrings: nil, state: state, deviceKeys: true)
        let dataModel = sut.makeDataModel()

        await dataModel.openVaultDidChange()

        #expect(try sut.fixture.savedState().vault.keyrings != nil)
        dataModel.itemsSearchQuery = "find me"
        await dataModel.reloadItems()
        #expect(dataModel.items.map(\.id) == [hidden.id])
        dataModel.itemsSearchQuery = "kill me"
        await dataModel.reloadItems()
        #expect(try sut.fixture.savedState().items.map(\.id) == [hidden.id.id, kept.id.id])
    }
}

// MARK: - While the device key opens it

extension OpenVaultPhraseKeyringsTests {
    /// With the password off, the vault's keyrings are where turning it off moved them, in the keychain, and nothing
    /// goes into its payload.
    @Test
    func vaultTheDeviceKeyOpens_usesTheKeyringsTurningThePasswordOffLeft() async throws {
        let keyrings = VaultPhraseKeyrings.random()
        let sut = try await Harness.encrypted(keyrings: nil, deviceKeys: true, openedWithTheDeviceKey: true)
        try await sut.device.storePasswordOffKeyrings(keyrings)

        #expect(try await sut.keyrings.ownKey(.killphrase) == keyrings.killphrase.ownKey)
        try await sut.keyrings.addKeysFromBackup([Self.restoredKillphraseKey], to: .searchPassphrase)

        var expected = keyrings
        expected.searchPassphrase.add([Self.restoredKillphraseKey])
        #expect(try await sut.device.passwordOffKeyrings() == expected)
        #expect(try sut.fixture.savedState().vault.keyrings == nil)
    }

    /// A vault whose password was turned off before vaults kept their own uses this device's keyrings, as it did.
    @Test
    func vaultTheDeviceKeyOpens_turnedOffBeforeVaultsKeptTheirOwn_usesTheDevicesKeyrings() async throws {
        let sut = try await Harness.encrypted(keyrings: nil, deviceKeys: true, openedWithTheDeviceKey: true)

        #expect(try await sut.keyrings.ownKey(.killphrase) == Self.deviceKillphraseKey)
        try await sut.keyrings.addKeysFromBackup([KeyData<32>.repeating(byte: 0xB3)], to: .killphrase)

        #expect(try await sut.device.killphrase.loadKeysFromBackups() == [
            Self.restoredKillphraseKey,
            .repeating(byte: 0xB3),
        ])
        #expect(try sut.fixture.savedState().vault.keyrings == nil)
    }

    /// Turning the password off keeps the keyrings in the keychain before the rekey takes them out of the payload. If
    /// they can't be kept, nothing changes: the vault keeps them, and its password.
    @Test
    func rekey_takingTheKeyringsOut_whenTheyCantBeKept_changesNothing() async throws {
        struct CantKeepThem: Error {}
        let keyrings = VaultPhraseKeyrings.random()
        let sut = try await Harness.encrypted(keyrings: keyrings)
        let before = try sut.fixture.bytes()

        await #expect(throws: CantKeepThem.self) {
            try await sut.store.rekey(
                to: .device(SymmetricKey(size: .bits256)),
                protection: EncryptedVaultFile.protection(for: .deviceKey),
                keyrings: .out { _ in throw CantKeepThem() },
            )
        }

        #expect(try sut.fixture.bytes() == before)
        #expect(try await sut.store.phraseKeyrings == keyrings)
        #expect(try await !sut.store.opensWithTheDeviceKey)
    }

    /// Taken out, they're given to be kept first, then gone from the payload in the rekey's own write.
    @Test
    func rekey_takingTheKeyringsOut_keepsThemThenTakesThemOutInTheSameWrite() async throws {
        let keyrings = VaultPhraseKeyrings.random()
        let sut = try await Harness.encrypted(keyrings: keyrings)
        let kept = SharedMutex<VaultPhraseKeyrings?>(nil)
        let deviceKey = SymmetricKey(size: .bits256)

        try await sut.store.rekey(
            to: .device(deviceKey),
            protection: EncryptedVaultFile.protection(for: .deviceKey),
            keyrings: .out { keyrings in kept.modify { $0 = keyrings } },
        )

        let contents = try VaultSlotFile(bytes: sut.fixture.bytes())
        let slot = try contents.openSlot(sut.fixture.slotIndex, with: .device(deviceKey))
        #expect(kept.value == keyrings)
        #expect(try EncryptedVaultPayload.decode(slot: slot, in: contents).vault.keyrings == nil)
        #expect(try await sut.store.phraseKeyrings == nil)
    }

    /// A rekey to the device key holds back a copy that was waiting for its turn: it's not saved into a payload the
    /// device key opens.
    @Test
    func updatePhraseKeyrings_onceTheDeviceKeyOpensTheVault_changesNothing() async throws {
        let sut = try await Harness.encrypted(keyrings: nil, openedWithTheDeviceKey: true)

        let saved = try await sut.store.updatePhraseKeyrings { $0 ?? .random() }

        #expect(saved == nil)
        #expect(try sut.fixture.savedState().vault.keyrings == nil)
    }
}

// MARK: - Restoring a backup

extension OpenVaultPhraseKeyringsTests {
    /// A backup's keys go where the vault keeps its keyrings: an encrypted vault's payload, or the keychain for the
    /// plain store. Either way its killphrases and search passphrases work.
    @MainActor
    @Test(arguments: [false, true])
    func restore_putsTheBackupsKeysWithTheVaultsAndItsPhrasesWork(intoAnEncryptedVault: Bool) async throws {
        let backupKillphraseKey = KeyData<32>.repeating(byte: 0xC1)
        let backupSearchPassphraseKey = KeyData<32>.repeating(byte: 0xC2)
        let armed = anySecureNote(title: "armed").wrapInAnyVaultItem(
            killphrase: KillphraseDigester(key: backupKillphraseKey).makeDigest(phrase: "kill me"),
        )
        let hidden = anySecureNote(title: "hidden").wrapInAnyVaultItem(
            visibility: .onlySearch,
            searchableLevel: .onlyPassphrase,
            searchPassphrase: SearchPassphraseDigester(key: backupSearchPassphraseKey).makeDigest(phrase: "find me"),
        )
        let backup = VaultApplicationPayload(
            userDescription: "",
            items: [armed, hidden],
            tags: [],
            killphraseKeys: [backupKillphraseKey],
            searchPassphraseKeys: [backupSearchPassphraseKey],
        )
        let sut = try await intoAnEncryptedVault ? Harness.encrypted(keyrings: .random()) : Harness.plain()
        let dataModel = sut.makeDataModel()
        await dataModel.openVaultDidChange()

        try await dataModel.importMerge(payload: backup)

        if intoAnEncryptedVault {
            let saved = try #require(try sut.fixture.savedState().vault.keyrings)
            #expect(saved.killphrase.keysFromBackups == [backupKillphraseKey])
            #expect(saved.searchPassphrase.keysFromBackups == [backupSearchPassphraseKey])
            #expect(try await sut.device.killphrase.loadAllKeys().isEmpty)
        } else {
            #expect(try await sut.device.killphrase.loadKeysFromBackups() == [backupKillphraseKey])
            #expect(try await sut.device.searchPassphrase.loadKeysFromBackups() == [backupSearchPassphraseKey])
        }
        dataModel.itemsSearchQuery = "find me"
        await dataModel.reloadItems()
        #expect(dataModel.items.map(\.id) == [hidden.id])
        dataModel.itemsSearchQuery = "kill me"
        await dataModel.reloadItems()
        #expect(try await sut.session.exportVault(userDescription: "").items.map(\.id) == [hidden.id])
    }

    /// A backup carries every key on the open vault's keyrings, and only its own: never another vault's, nor the
    /// keychain's while the vault has its own.
    @MainActor
    @Test
    func makeExport_carriesTheOpenVaultsKeysOnly() async throws {
        var keyrings = VaultPhraseKeyrings.random()
        keyrings.killphrase.add([.repeating(byte: 0xC3)])
        let sut = try await Harness.encrypted(keyrings: keyrings, deviceKeys: true)
        let dataModel = sut.makeDataModel()

        let export = try await dataModel.makeExport(userDescription: "")

        #expect(export.killphraseKeys == keyrings.killphrase.allKeys)
        #expect(export.searchPassphraseKeys == keyrings.searchPassphrase.allKeys)
    }
}

// MARK: - The data model following the open vault

extension OpenVaultPhraseKeyringsTests {
    /// Each vault's phrases are checked with its own keys: switching vault reads the next vault's, and locking forgets
    /// them.
    @MainActor
    @Test
    func openVaultDidChange_makesTheDigestersFromTheOpenVaultsKeysAndForgetsThemWhenItLocks() async throws {
        let realKeyrings = VaultPhraseKeyrings.random()
        let duressKeyrings = VaultPhraseKeyrings.random()
        let sut = try await Harness.encrypted(keyrings: realKeyrings)
        var duressState = VaultRecordState.empty
        duressState.vault.keyrings = duressKeyrings
        let duress = try await sut.fixture.addingVault(
            inSlot: (sut.fixture.slotIndex + 3) % VaultSlotFile.slotCount,
            state: duressState,
        )
        let dataModel = sut.makeDataModel()
        let realDigest = KillphraseDigester(key: realKeyrings.killphrase.ownKey).makeDigest(phrase: "kill me")

        let duressStore = try await duress.openStore()

        await dataModel.openVaultDidChange()
        let realDigester = try #require(dataModel.killphraseDigester)
        await sut.session.switchTo(.unlocked(duressStore))
        await dataModel.openVaultDidChange()
        let duressDigester = try #require(dataModel.killphraseDigester)
        await sut.session.lock()
        await dataModel.openVaultDidChange()

        #expect(realDigester.matches(query: "kill me", salt: realDigest.salt, digest: realDigest.digest))
        #expect(!duressDigester.matches(query: "kill me", salt: realDigest.salt, digest: realDigest.digest))
        #expect(dataModel.killphraseDigester == nil)
        #expect(dataModel.searchPassphraseDigester == nil)
    }
}

// MARK: - Helpers

extension OpenVaultPhraseKeyringsTests {
    private static func slotBytes(_ fixture: EncryptedVaultFixture) throws -> Data {
        let contents = try VaultSlotFile(bytes: fixture.bytes())
        return contents.bytes[contents.slotRange(fixture.slotIndex)]
    }

    private struct Harness {
        let session: VaultStoreSession
        let storage: InMemorySecureStorage
        let fileSystem: FaultInjectingSlotFileSystem
        /// The encrypted vault's file, if the session opened one.
        let encryptedFixture: EncryptedVaultFixture?
        let encryptedStore: EncryptedVaultStore?

        var device: DevicePhraseKeyrings {
            DevicePhraseKeyrings(secureStorage: storage)
        }

        var keyrings: OpenVaultPhraseKeyrings {
            OpenVaultPhraseKeyrings(session: session, device: device)
        }

        var fixture: EncryptedVaultFixture {
            get throws { try #require(encryptedFixture) }
        }

        var store: EncryptedVaultStore {
            get throws { try #require(encryptedStore) }
        }

        /// The plain store, in memory, with no keys in the keychain yet.
        static func plain() async throws -> Harness {
            try Harness(
                session: VaultStoreSession(target: .plain(PersistedLocalVaultStore.inMemory())),
                storage: InMemorySecureStorage(),
                fileSystem: FaultInjectingSlotFileSystem(wrapping: InMemorySlotFileSystem()),
                encryptedFixture: nil,
                encryptedStore: nil,
            )
        }

        /// An encrypted vault, open, with `keyrings` in its payload.
        ///
        /// - Parameters:
        ///   - deviceKeys: Whether the keychain has this device's keyrings, as an earlier version left them: its own
        ///     keys, and a killphrase key a restored backup brought.
        ///   - openedWithTheDeviceKey: Whether the device key opens it, with the password off.
        static func encrypted(
            keyrings: VaultPhraseKeyrings?,
            state: VaultRecordState = .empty,
            deviceKeys: Bool = false,
            openedWithTheDeviceKey: Bool = false,
        ) async throws -> Harness {
            var state = state
            state.vault.keyrings = keyrings
            let fileSystem = FaultInjectingSlotFileSystem(wrapping: InMemorySlotFileSystem())
            let fixture = try EncryptedVaultFixture(
                fileSystem: fileSystem,
                state: state,
                payloadVersion: keyrings == nil ? 1 : EncryptedVaultPayload.currentVersion,
            )
            let file = EncryptedVaultFile(
                directory: fixture.file.directory,
                fileSystem: fileSystem,
                protection: EncryptedVaultFile.protection(for: openedWithTheDeviceKey ? .deviceKey : .password),
            )
            let contents = try #require(try await file.open())
            let store = try EncryptedVaultStore(
                file: file,
                contents: contents,
                slot: contents.openSlot(fixture.slotIndex, with: fixture.rootKey),
                wrapStamper: VaultDeviceWrapStamper.inMemory(),
            )
            let storage = InMemorySecureStorage()
            if deviceKeys {
                let device = DevicePhraseKeyrings(secureStorage: storage)
                await storage.storeSilent(
                    data: OpenVaultPhraseKeyringsTests.deviceKillphraseKey.data,
                    forKey: VaultIdentifiers.SecureStorageKey.killphraseKey.keychainService,
                )
                await storage.storeSilent(
                    data: OpenVaultPhraseKeyringsTests.deviceSearchPassphraseKey.data,
                    forKey: VaultIdentifiers.SecureStorageKey.searchPassphraseKey.keychainService,
                )
                try await device.killphrase.addKeysFromBackup([OpenVaultPhraseKeyringsTests.restoredKillphraseKey])
            }
            return Harness(
                session: VaultStoreSession(target: .unlocked(store)),
                storage: storage,
                fileSystem: fileSystem,
                encryptedFixture: fixture,
                encryptedStore: store,
            )
        }

        /// The data model, reading the open vault's keyrings, as the app has it.
        @MainActor
        func makeDataModel() -> VaultDataModel {
            anyVaultDataModel(
                vaultStore: session,
                vaultTagStore: session,
                vaultImporter: session,
                vaultDeleter: session,
                vaultKillphraseDeleter: session,
                killphraseKeyStore: keyrings.killphraseKeys,
                searchPassphraseKeyStore: keyrings.searchPassphraseKeys,
            )
        }
    }
}
