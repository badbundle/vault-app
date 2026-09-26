import CryptoKit
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import VaultFeed

/// Making a duress vault from an open encrypted vault (VAULT-51): where it goes, what it holds, the password rules,
/// and that the real vault is never touched.
struct DuressVaultTests {
    private let realSlot = 6
}

// MARK: - Making one

extension DuressVaultTests {
    @Test
    func makeDuressVault_createsAnEmptyVaultInTheFirstDuressSlotThatThePasswordOpens() async throws {
        let fixture = try DuressFixture(realSlot: realSlot, items: [uniqueVaultItem()])
        let real = try fixture.open(slot: realSlot, password: "real")
        let realDuressSlots = await real.records.state.vault.duressSlots

        try await real.makeDuressVault(password: "duress")

        #expect(try fixture.slotsOpened(by: "duress") == [realDuressSlots[0]])
        let duress = try fixture.state(ofSlot: realDuressSlots[0], password: "duress")
        #expect(duress.items.isEmpty)
        #expect(duress.tags.isEmpty)
        #expect(Array(duress.vault.duressSlots.prefix(9)) == Array(realDuressSlots.dropFirst()))
        #expect(VaultDuressSlots.isValid(duress.vault.duressSlots, forSlot: realDuressSlots[0]))
        #expect(!duress.vault.duressSlots.contains(realSlot))
    }

    /// The real vault's slot isn't written at all, so its password still opens it to exactly what it held, and the
    /// file shows no change in it. Only the duress vault's slot changes.
    @Test
    func makeDuressVault_leavesEveryOtherSlotAsItWas() async throws {
        let fixture = try DuressFixture(realSlot: realSlot, items: [uniqueVaultItem()])
        let real = try fixture.open(slot: realSlot, password: "real")
        let target = await real.records.state.vault.duressSlots[0]
        let before = try fixture.contents()
        let realStateBefore = try fixture.state(ofSlot: realSlot, password: "real")

        try await real.makeDuressVault(password: "duress")

        let after = try fixture.contents()
        for index in VaultSlotFile.slotIndices where index != target {
            #expect(after.bytes[after.slotRange(index)] == before.bytes[before.slotRange(index)])
        }
        #expect(after.bytes[after.slotRange(target)] != before.bytes[before.slotRange(target)])
        #expect(try fixture.state(ofSlot: realSlot, password: "real") == realStateBefore)
        #expect(try fixture.slotsOpened(by: "real") == [realSlot])
    }

    /// The vault that made it keeps working as before: it saves to its own slot, and the duress vault stays.
    @Test
    func makeDuressVault_thenSavingTheRealVault_keepsBoth() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let target = await real.records.state.vault.duressSlots[0]
        try await real.makeDuressVault(password: "duress")

        let item = try await real.insert(item: uniqueVaultItem().makeWritable())

        #expect(try fixture.state(ofSlot: realSlot, password: "real").items.map(\.id) == [item.rawValue])
        #expect(try fixture.slotsOpened(by: "duress") == [target])
    }

    /// Making another duress vault replaces the one before: it goes in the same slot, and the old password opens
    /// nothing any more.
    @Test
    func makeDuressVault_again_replacesThePreviousOne() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let target = await real.records.state.vault.duressSlots[0]
        try await real.makeDuressVault(password: "first")

        try await real.makeDuressVault(password: "second")

        #expect(try fixture.slotsOpened(by: "second") == [target])
        #expect(try fixture.slotsOpened(by: "first").isEmpty)
    }

    /// It's made the same way from inside a duress vault: in that vault's first duress slot, handing on the rest.
    @Test
    func makeDuressVault_fromADuressVault_goesInItsFirstDuressSlot() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let first = await real.records.state.vault.duressSlots[0]
        try await real.makeDuressVault(password: "first")
        let duress = try fixture.open(slot: first, password: "first")
        let duressSlots = await duress.records.state.vault.duressSlots

        try await duress.makeDuressVault(password: "second")

        #expect(try fixture.slotsOpened(by: "second") == [duressSlots[0]])
        #expect(try fixture.slotsOpened(by: "first") == [first])
        #expect(try fixture.slotsOpened(by: "real") == [realSlot])
    }

    /// The design's guarantee, through the store: making a duress vault from the one before, eleven times over,
    /// starting from the real vault, never writes the real vault's slot.
    @Test
    func chainOfElevenDuressVaults_neverTouchesTheRealVault() async throws {
        let realItem = uniqueVaultItem()
        let fixture = try DuressFixture(realSlot: realSlot, items: [realItem])
        let realSlotBytes = try fixture.slotBytes(realSlot)
        var password = "real"
        var slot = realSlot

        for level in 1 ... 11 {
            let vault = try fixture.open(slot: slot, password: password)
            let target = await vault.records.state.vault.duressSlots[0]
            try await vault.makeDuressVault(password: "duress \(level)")
            password = "duress \(level)"
            slot = target
            #expect(slot != realSlot)
            #expect(try fixture.slotBytes(realSlot) == realSlotBytes)
        }

        #expect(try fixture.slotsOpened(by: "real") == [realSlot])
        #expect(try fixture.state(ofSlot: realSlot, password: "real").items.map(\.id) == [realItem.id.rawValue])
    }
}

// MARK: - Passwords

extension DuressVaultTests {
    @Test
    func makeDuressVault_withThisVaultsOwnPassword_isRefusedAndChangesNothing() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let bytesBefore = try fixture.contents().bytes

        await #expect(throws: VaultDuressVaultError.matchesAppLockPassword) {
            try await real.makeDuressVault(password: "real")
        }

        #expect(try fixture.contents().bytes == bytesBefore)
    }

    /// The check is the same in every vault: a duress vault refuses its own password too.
    @Test
    func makeDuressVault_fromADuressVaultWithItsOwnPassword_isRefused() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let first = await real.records.state.vault.duressSlots[0]
        try await real.makeDuressVault(password: "first")
        let duress = try fixture.open(slot: first, password: "first")
        let bytesBefore = try fixture.contents().bytes

        await #expect(throws: VaultDuressVaultError.matchesAppLockPassword) {
            try await duress.makeDuressVault(password: "first")
        }

        #expect(try fixture.contents().bytes == bytesBefore)
    }

    /// Keyboards can compose accented letters either way, and both are the same password.
    @Test
    func makeDuressVault_withThisVaultsPasswordComposedAnotherWay_isRefused() async throws {
        let fixture = try DuressFixture(realSlot: realSlot, realPassword: "caf\u{E9}")
        let real = try fixture.open(slot: realSlot, password: "caf\u{E9}")

        await #expect(throws: VaultDuressVaultError.matchesAppLockPassword) {
            try await real.makeDuressVault(password: "cafe\u{301}")
        }
    }

    /// A password that opens another vault is accepted without a word: refusing it would tell someone inside the
    /// duress vault that the other vault exists. The other vault isn't destroyed; its slot stays exactly as it was.
    @Test
    func makeDuressVault_withAnotherVaultsPassword_isAcceptedAndLeavesThatVault() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let first = await real.records.state.vault.duressSlots[0]
        try await real.makeDuressVault(password: "first")
        let duress = try fixture.open(slot: first, password: "first")
        let second = await duress.records.state.vault.duressSlots[0]
        let realSlotBytes = try fixture.slotBytes(realSlot)

        try await duress.makeDuressVault(password: "real")

        #expect(try fixture.slotsOpened(by: "real") == [realSlot, second].sorted())
        #expect(try fixture.slotBytes(realSlot) == realSlotBytes)
    }
}

// MARK: - Every vault alike

extension DuressVaultTests {
    /// Nothing in a duress vault's payload sets it apart from the real vault's: an empty real vault and a new duress
    /// vault have payloads of exactly the same shape.
    @Test
    func duressVaultPayload_hasTheSameShapeAsAnEmptyRealVaults() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let target = await real.records.state.vault.duressSlots[0]
        try await real.makeDuressVault(password: "duress")

        let realPayload = try fixture.payloadJSON(ofSlot: realSlot, password: "real")
        let duressPayload = try fixture.payloadJSON(ofSlot: target, password: "duress")

        #expect(Self.shape(of: duressPayload) == Self.shape(of: realPayload))
        #expect(try fixture.payload(ofSlot: target, password: "duress").version == EncryptedVaultPayload.currentVersion)
    }

    /// With items in the real vault, the payloads still have the same sections, and the vault's own section is
    /// shaped the same, with ten duress slots in each.
    @Test
    func duressVaultPayload_hasTheSameSectionsAsARealVaultWithItems() async throws {
        let tag = anyVaultItemTag()
        let fixture = try DuressFixture(realSlot: realSlot, items: [uniqueVaultItem(tags: [tag.id])], tags: [tag])
        let real = try fixture.open(slot: realSlot, password: "real")
        let target = await real.records.state.vault.duressSlots[0]
        try await real.makeDuressVault(password: "duress")

        let realPayload = try #require(try fixture.payloadJSON(ofSlot: realSlot, password: "real") as? [String: Any])
        let duressPayload = try #require(try fixture.payloadJSON(ofSlot: target, password: "duress") as? [String: Any])

        #expect(Set(duressPayload.keys) == Set(realPayload.keys))
        #expect(try Self.shape(of: #require(duressPayload["vault"])) == Self.shape(of: #require(realPayload["vault"])))
        let duressSlots = try #require((duressPayload["vault"] as? [String: Any])?["duressSlots"] as? [Int])
        let realDuressSlots = try #require((realPayload["vault"] as? [String: Any])?["duressSlots"] as? [Int])
        #expect(duressSlots.count == realDuressSlots.count)
    }

    /// Making one takes the same steps whichever vault it's made from: one derivation, a trial of that vault's own
    /// slot, and one replacement of the file, in the same time.
    @Test
    func makeDuressVault_takesTheSameStepsFromTheRealVaultAndADuressVault() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let first = await real.records.state.vault.duressSlots[0]
        try await real.makeDuressVault(password: "first")

        // The duress vault makes its own first: the real vault's replaces it.
        let spied = try [(first, "first"), (realSlot, "real")].map { slot, password in
            let log = SharedMutex([String]())
            let clock = ManualUnlockClock()
            let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.fileSystem)
            let store = try fixture.open(
                slot: slot,
                password: password,
                fileSystem: fileSystem,
                work: SpyUnlockWork(log: log, clock: clock),
            )
            return (store: store, password: password, log: log, clock: clock, fileSystem: fileSystem)
        }
        var steps = [[String]]()
        var elapsed = [Duration]()
        for vault in spied {
            let start = vault.clock.now

            try await vault.store.makeDuressVault(password: "made from \(vault.password)")

            let workSteps = vault.log.value.map { $0.hasPrefix("try slot") ? "try its own slot" : $0 }
            steps.append(workSteps + vault.fileSystem.log)
            elapsed.append(start.duration(to: vault.clock.now))
        }

        let expected = ["derive", "try its own slot"] + Self.stepsOfMaking + ["unlock"]
        #expect(steps == [expected, expected])
        #expect(elapsed[0] == elapsed[1])
    }

    /// The shape of a JSON value: its keys, and the kinds of its values, but not the values themselves.
    static func shape(of json: Any) -> String {
        switch json {
        case let object as [String: Any]:
            "{" + object.sorted { $0.key < $1.key }.map { "\($0.key): \(shape(of: $0.value))" }
                .joined(separator: ", ") + "}"
        case let array as [Any]:
            "[" + Set(array.map { shape(of: $0) }).sorted().joined(separator: " | ") + "]"
        case is String:
            "string"
        case is NSNumber:
            "number"
        default:
            "null"
        }
    }
}

// MARK: - Failures

extension DuressVaultTests {
    /// The steps of making one: reading the header to derive, then a save's steps.
    private static let stepsOfMaking = ["read the start of vault-slots.v1"] + EncryptedVaultStoreTests.stepsOfASave

    /// Up to and including the rename, a failure leaves the file exactly as it was, and no temp file behind.
    @Test(arguments: 1 ... EncryptedVaultStoreTests.renameStep + 1)
    func makeDuressVault_failingAtAnyStepUpToTheRename_leavesTheFileAsItWas(step: Int) async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.fileSystem)
        let real = try fixture.open(slot: realSlot, password: "real", fileSystem: fileSystem)
        let bytesBefore = try fixture.contents().bytes

        fileSystem.inject(.fail(atStep: step))
        await #expect(throws: (any Error).self, "failing at \(Self.stepsOfMaking[step - 1])") {
            try await real.makeDuressVault(password: "duress")
        }

        #expect(try fixture.contents().bytes == bytesBefore)
        #expect(try fixture.temporaryFileNames().isEmpty)
        #expect(try fixture.slotsOpened(by: "duress").isEmpty)
    }

    @Test
    func makeDuressVault_whoseFileDoesNotReadBackAsWritten_isNotUsed() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.fileSystem)
        let real = try fixture.open(slot: realSlot, password: "real", fileSystem: fileSystem)
        let bytesBefore = try fixture.contents().bytes

        fileSystem.inject(.corruptReadBack)
        await #expect(throws: EncryptedVaultStoreError.verificationFailed) {
            try await real.makeDuressVault(password: "duress")
        }

        #expect(try fixture.contents().bytes == bytesBefore)
    }

    /// A vault whose list of duress slots isn't one the app writes can't say where a duress vault goes, so it
    /// makes none, rather than guessing.
    @Test
    func makeDuressVault_fromAVaultWithoutValidDuressSlots_throwsUnavailable() async throws {
        let fixture = try DuressFixture(realSlot: realSlot, duressSlots: [])
        let real = try fixture.open(slot: realSlot, password: "real")
        let bytesBefore = try fixture.contents().bytes

        await #expect(throws: VaultDuressVaultError.unavailable) {
            try await real.makeDuressVault(password: "duress")
        }

        #expect(try fixture.contents().bytes == bytesBefore)
    }

    /// If this vault's slot has been rewrapped or replaced since it was opened, it isn't this vault's any more.
    @Test
    func makeDuressVault_afterThisVaultsSlotWasReplaced_throwsSlotLost() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        try fixture.replaceVault(inSlot: realSlot, password: "someone else")

        await #expect(throws: EncryptedVaultStoreError.slotLost) {
            try await real.makeDuressVault(password: "duress")
        }
    }
}

// MARK: - Store session

extension DuressVaultTests {
    @Test
    func session_unlocked_makesTheDuressVault() async throws {
        let fixture = try DuressFixture(realSlot: realSlot)
        let real = try fixture.open(slot: realSlot, password: "real")
        let target = await real.records.state.vault.duressSlots[0]
        let sut = VaultStoreSession(target: .unlocked(real))

        try await sut.makeDuressVault(password: "duress")

        #expect(try fixture.slotsOpened(by: "duress") == [target])
    }

    @Test
    func session_plain_throwsNotEncrypted() async throws {
        let sut = VaultStoreSession(target: .plain(GatedVaultStore()))

        await #expect(throws: VaultDuressVaultError.notEncrypted) {
            try await sut.makeDuressVault(password: "duress")
        }
    }

    @Test
    func session_locked_throwsLocked() async throws {
        let sut = VaultStoreSession(target: .locked)

        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.makeDuressVault(password: "duress")
        }
    }
}

// MARK: - Fixture

/// A vault file whose vaults open with real passwords, derived with cheap parameters.
private struct DuressFixture {
    let fileSystem = InMemorySlotFileSystem()
    let file: EncryptedVaultFile
    /// Each vault opened is given a later wrap time than the one before, so the most recent is always clear.
    private let clock = SharedMutex(Date(timeIntervalSince1970: 1_790_000_000))

    /// A file with the real vault in `realSlot`, with ten random duress slots unless given others, and every other
    /// slot random.
    init(
        realSlot: Int,
        realPassword: String = "real",
        items: [VaultItem] = [],
        tags: [VaultItemTag] = [],
        duressSlots: [Int]? = nil,
    ) throws {
        file = EncryptedVaultFile(directory: EncryptedVaultFixture.inMemoryDirectory, fileSystem: fileSystem)
        var contents = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
        var state = try EncryptedVaultStoreTests.state(items: items, tags: tags)
        state.vault.duressSlots = duressSlots ?? VaultDuressSlots.forFirstVault(inSlot: realSlot)
        try contents.createVault(
            inSlot: realSlot,
            rootKey: contents.header.passwordKey(for: realPassword),
            payload: EncryptedVaultPayload.encode(state),
            wrappedAt: nextDate(),
        )
        try fileSystem.createFile(at: file.url, contents: contents.bytes)
    }

    /// The store for the vault `password` opens in `slot`, as unlocking would make it.
    func open(
        slot: Int,
        password: String,
        fileSystem: (any SlotFileSystem)? = nil,
        work: any VaultUnlockWork = LiveVaultUnlockWork(),
    ) throws -> EncryptedVaultStore {
        let contents = try contents()
        let file = EncryptedVaultFile(directory: file.directory, fileSystem: fileSystem ?? self.fileSystem)
        let clock = clock
        return try EncryptedVaultStore(
            file: file,
            contents: contents,
            slot: contents.openSlot(slot, with: contents.header.passwordKey(for: password)),
            currentDate: { clock.modify { date in
                date += 60
                return date
            } },
            work: work,
        )
    }

    /// Writes a new vault into the slot, as if another process had replaced it.
    func replaceVault(inSlot slot: Int, password: String) throws {
        var contents = try contents()
        try contents.createVault(
            inSlot: slot,
            rootKey: contents.header.passwordKey(for: password),
            payload: EncryptedVaultPayload.encode(.empty),
            wrappedAt: nextDate(),
        )
        fileSystem.setContents(contents.bytes, at: file.url)
    }

    func contents() throws -> VaultSlotFile {
        try VaultSlotFile(bytes: #require(try fileSystem.contents(of: file.url)))
    }

    func slotBytes(_ index: Int) throws -> Data {
        let contents = try contents()
        return contents.bytes[contents.slotRange(index)]
    }

    /// The slots whose key box the password opens.
    func slotsOpened(by password: String) throws -> [Int] {
        let contents = try contents()
        let key = try contents.header.passwordKey(for: password)
        return VaultSlotFile.slotIndices.filter { (try? contents.openSlot($0, with: key)) != nil }
    }

    func payload(ofSlot slot: Int, password: String) throws -> VaultSlotPayload {
        let contents = try contents()
        return try contents.openPayload(of: contents.openSlot(slot, with: contents.header.passwordKey(for: password)))
    }

    func payloadJSON(ofSlot slot: Int, password: String) throws -> Any {
        try JSONSerialization.jsonObject(with: payload(ofSlot: slot, password: password).data)
    }

    func state(ofSlot slot: Int, password: String) throws -> VaultRecordState {
        try EncryptedVaultPayload.decode(payload(ofSlot: slot, password: password))
    }

    func temporaryFileNames() throws -> [String] {
        try fileSystem.contentsOfDirectory(at: file.directory)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix(EncryptedVaultFile.temporaryFilePrefix) }
    }

    private func nextDate() -> Date {
        clock.modify { date in
            date += 60
            return date
        }
    }
}
