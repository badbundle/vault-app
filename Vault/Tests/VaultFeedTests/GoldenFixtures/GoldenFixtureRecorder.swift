import CryptoEngine
import Foundation
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// Makes the golden fixtures that aren't in `Fixtures/` yet, with the app's own code, and writes them into the source
/// tree. It only runs when it's asked to:
///
/// ```
/// TEST_RUNNER_VAULT_RECORD_FIXTURES=1 xcodebuild test … -only-testing:VaultFeedTests/GoldenFixtureRecorder
/// ```
///
/// It never replaces a fixture that's there. It prints the values the code chose at random that the tests check, to
/// be copied into the fixture's definition. See `Fixtures/README.md`.
@Suite(.enabled(if: GoldenFixture.isRecording))
struct GoldenFixtureRecorder {
    /// The encrypted items come first, because the slot file's real vault holds them.
    @Test
    func recordMissingFixtures() async throws {
        for fixture in EncryptedItemFixture.all where !GoldenFixture.isRecorded(fixture.name) {
            try record(fixture)
        }
        if !GoldenFixture.isRecorded(SlotFileFixture.name) {
            try await recordSlotFile()
        }
    }
}

// MARK: - Encrypted items

extension GoldenFixtureRecorder {
    struct NotEncryptable: Error {}

    /// Encrypts the item as the app does when it's given a new password, with a key derived with a new salt, and
    /// stores it in a payload of its own.
    private func record(_ fixture: EncryptedItemFixture) throws {
        let key = try VaultKeyDeriver.Item.Fast.v1.createEncryptionKey(password: fixture.password)
        let item = try VaultItem(
            metadata: fixture.metadata,
            item: .encryptedItem(encrypt(fixture.decrypted, with: VaultItemEncryptor(key: key))),
        )
        let record = try PersistedVaultItemEncoder().encode(
            item: item.makeWritable(),
            writeUpdateContext: item.makeImportingContext(),
        )
        let payload = try EncryptedVaultPayload.encode(VaultRecordState(items: [record], tags: []))
        try GoldenFixture.record(payload.data, named: fixture.name)
    }

    private func encrypt(_ payload: VaultItem.Payload, with encryptor: VaultItemEncryptor) throws -> EncryptedItem {
        switch payload {
        case let .secureNote(note): try encryptor.encrypt(item: note)
        case let .recoveryPhrase(phrase): try encryptor.encrypt(item: phrase)
        case .otpCode, .encryptedItem: throw NotEncryptable()
        }
    }
}

// MARK: - Slot file

extension GoldenFixtureRecorder {
    /// Makes the file as the app does: the real vault as turning on the App Lock Password creates it
    /// (`VaultEncryptionConverter`), then a duress vault made from it by its store, which is given its items by
    /// importing them. Every other slot stays random.
    ///
    /// It stores the header and the slots that hold the vaults, in the order they're in the file.
    private func recordSlotFile() async throws {
        let real = SlotFileFixture.real
        let duress = SlotFileFixture.duress
        let encryptedItems = try real.encryptedItems.map {
            try EncryptedItemFixture.storedItem(in: Data(contentsOf: GoldenFixture.sourceURL(named: $0.name)))
        }
        try await withTemporaryDirectory { directory in
            let file = EncryptedVaultFile(directory: directory)
            var contents = try VaultSlotFile(kdfParameters: SlotFileFixture.kdfParameters)
            var state = try EncryptedVaultStoreTests.state(items: real.plainItems + encryptedItems, tags: real.tags)
            state.vault = VaultMetadata(
                duressSlots: VaultDuressSlots.forFirstVault(inSlot: real.slot),
                settings: real.settings,
            )
            let realSlot = try contents.createVault(
                inSlot: real.slot,
                rootKey: contents.header.passwordKey(for: real.password),
                payload: EncryptedVaultPayload.encode(state),
                wrappedAt: real.wrappedAt,
            )
            try contents.bytes.write(to: file.url)

            let realStore = EncryptedVaultStore(
                file: file,
                slot: realSlot,
                state: state,
                wrapStamper: VaultDeviceWrapStamper.inMemory { duress.wrappedAt },
            )
            try await realStore.makeDuressVault(password: duress.password)

            let withDuress = try #require(try await file.open())
            let duressStore = try EncryptedVaultStore(
                file: file,
                contents: withDuress,
                slot: withDuress.openSlot(
                    state.vault.duressSlots[0],
                    with: withDuress.header.passwordKey(for: duress.password),
                ),
                currentDate: { duress.wrappedAt },
            )
            try await duressStore.importAndMergeVault(payload: VaultApplicationPayload(
                userDescription: "",
                items: duress.plainItems,
                tags: duress.tags,
            ))
            try await duressStore.updateBackupSettings { $0 = duress.settings }

            let recorded = try #require(try await file.open())
            let vaultSlots = [real.slot, state.vault.duressSlots[0]].sorted()
            var stored = recorded.bytes.prefix(VaultSlotFile.Header.length)
            for index in vaultSlots {
                stored.append(recorded.bytes[recorded.slotRange(index)])
            }
            try GoldenFixture.record(stored, named: SlotFileFixture.name)
            try printRecordedValues(of: recorded, storedSlots: vaultSlots)
        }
    }

    private func printRecordedValues(of file: VaultSlotFile, storedSlots: [Int]) throws {
        var lines = ["Recorded \(SlotFileFixture.name). Copy into SlotFileFixture:"]
        lines.append("stored slots: \(storedSlots)")
        lines.append("salt: \(file.header.salt.toHexString())")
        for vault in SlotFileFixture.vaults {
            let key = try file.header.passwordKey(for: vault.password)
            for index in VaultSlotFile.slotIndices {
                guard let slot = try? file.openSlot(index, with: key) else { continue }
                let duressSlots = try EncryptedVaultPayload.decode(slot: slot, in: file).vault.duressSlots
                lines.append("\(vault.name): slot \(index), generation \(slot.generation), duress slots \(duressSlots)")
            }
        }
        // Only when recording, which has to be asked for.
        // swiftlint:disable:next no_direct_standard_out_logs
        print(lines.joined(separator: "\n"))
    }
}
