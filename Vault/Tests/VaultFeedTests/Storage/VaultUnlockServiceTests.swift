import CryptoKit
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

struct VaultUnlockServiceTests {
    private let deadline = Duration.seconds(1)
    private let realSlot = 4
    private let duressSlot = 11
}

// MARK: - Unlocking

extension VaultUnlockServiceTests {
    @Test
    func unlock_withTheRealPassword_opensItsVaultAtTheDeadline() async throws {
        let item = uniqueVaultItem()
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [item])])
        let start = sut.clock.now

        let result = try await sut.service.unlock(password: "real")

        #expect(result == .unlocked)
        #expect(sut.clock.sleeps == [start.advanced(by: deadline)])
        #expect(try await sut.session.retrieve(query: .init()).items == [item])
        #expect(sut.log.value.last == "reset the count")
    }

    @Test
    func unlock_withADuressPassword_opensTheDuressVault() async throws {
        let duressItem = uniqueVaultItem()
        let sut = try makeSUT(vaults: [
            .init(password: "real", slot: realSlot, items: [uniqueVaultItem()]),
            .init(password: "duress", slot: duressSlot, items: [duressItem]),
        ])

        let result = try await sut.service.unlock(password: "duress")

        #expect(result == .unlocked)
        #expect(try await sut.session.retrieve(query: .init()).items == [duressItem])
    }

    @Test
    func unlock_withAWrongPassword_opensNothingAtTheDeadline() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [uniqueVaultItem()])])
        let start = sut.clock.now

        let result = try await sut.service.unlock(password: "wrong")

        #expect(result == .wrongPassword)
        #expect(sut.clock.sleeps == [start.advanced(by: deadline)])
        #expect(await sut.session.isLocked)
        #expect(!sut.log.value.contains("reset the count"))
    }

    /// Real, duress and wrong passwords take the same steps, the same number of times, open a body of the same
    /// length, and return at the deadline, even though opening a body that opens takes longer than the decoy.
    @Test
    func everyPassword_doesTheSameWorkAndReturnsAtTheDeadline() async throws {
        let vaults: [TestVault] = [
            .init(password: "real", slot: realSlot, items: [uniqueVaultItem()]),
            .init(password: "duress", slot: duressSlot, items: []),
        ]
        let timings = SpyUnlockWork.Timings(body: .milliseconds(80), bodyThatFails: .milliseconds(5))
        var logs = [[String]]()
        var bodyLengths = [[Int]]()
        var returnedAfter = [Duration]()

        for password in ["real", "duress", "wrong"] {
            let sut = try makeSUT(vaults: vaults, timings: timings)
            let start = sut.clock.now
            _ = try await sut.service.unlock(password: password)
            returnedAfter.append(start.duration(to: sut.clock.now))
            logs.append(sut.log.value.filter { $0 != "reset the count" })
            bodyLengths.append(sut.work.bodyLengths)
        }

        let expectedSteps = ["count the attempt", "derive"]
            + VaultSlotFile.slotIndices.map { "try slot \($0)" }
            + ["open a body"]
        #expect(logs == Array(repeating: expectedSteps, count: 3))
        #expect(bodyLengths == Array(repeating: [(1 << 20) - VaultSlotFile.bodyOffset], count: 3))
        #expect(returnedAfter == Array(repeating: deadline, count: 3))
    }

    @Test
    func unlock_passwordOpeningMoreThanOneSlot_opensTheMostRecentlyWrapped() async throws {
        let newer = uniqueVaultItem()
        let sut = try makeSUT(vaults: [
            .init(password: "same", slot: 2, items: [uniqueVaultItem()], wrappedAt: Date(timeIntervalSince1970: 1000)),
            .init(password: "same", slot: 9, items: [newer], wrappedAt: Date(timeIntervalSince1970: 2000)),
            .init(password: "same", slot: 14, items: [uniqueVaultItem()], wrappedAt: Date(timeIntervalSince1970: 1500)),
        ])

        _ = try await sut.service.unlock(password: "same")

        #expect(try await sut.session.retrieve(query: .init()).items == [newer])
    }

    /// Keyboards can compose accented letters either way, and both must open the vault.
    @Test
    func unlock_derivesFromTheComposedFormOfThePassword() async throws {
        let sut = try makeSUT(vaults: [.init(password: "caf\u{E9}", slot: realSlot, items: [])])

        let result = try await sut.service.unlock(password: "cafe\u{301}")

        #expect(result == .unlocked)
    }

    @Test
    func unlock_passwordOpeningADamagedVault_throwsAtTheDeadline() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [uniqueVaultItem()])])
        try await sut.damageBody(ofSlot: realSlot)
        let start = sut.clock.now

        await #expect(throws: VaultSlotFileError.bodyDidNotOpen) {
            try await sut.service.unlock(password: "real")
        }

        #expect(sut.clock.sleeps == [start.advanced(by: deadline)])
        #expect(await sut.session.isLocked)
        #expect(!sut.log.value.contains("reset the count"))
    }

    @Test
    func unlock_withoutAVaultFile_throwsWithoutCountingAnAttempt() async throws {
        let sut = try makeSUT(vaults: [])
        try sut.fileSystem.removeItem(at: sut.file.url)

        await #expect(throws: VaultUnlockError.noEncryptedVault) {
            try await sut.service.unlock(password: "real")
        }

        #expect(sut.log.value.isEmpty)
    }

    @Test
    func unlock_whileAnotherAttemptIsUnderway_throws() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])
        sut.clock.hold()
        let first = Task { try await sut.service.unlock(password: "real") }
        await sut.clock.waitUntilHolding()

        await #expect(throws: VaultUnlockError.attemptUnderway) {
            try await sut.service.unlock(password: "real")
        }

        sut.clock.release()
        #expect(try await first.value == .unlocked)
    }
}

// MARK: - The attempt counter

extension VaultUnlockServiceTests {
    @Test
    func unlock_countsTheAttemptBeforeDerivingAndResetsItOnceUnlocked() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])

        _ = try await sut.service.unlock(password: "real")

        let log = sut.log.value
        #expect(log.first == "count the attempt")
        #expect(log.dropFirst().first == "derive")
        #expect(log.last == "reset the count")
    }

    @Test
    func unlock_whileTheUserMustWait_triesNothing() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])
        // Five wrong attempts in a row, the latest 20 seconds ago: a minute's wait, 40 seconds of it left.
        sut.attemptStorage.setRecord(count: 5, latestAt: sut.attemptClock.now)
        sut.attemptClock.advance(by: .seconds(20))

        let result = try await sut.service.unlock(password: "real")

        #expect(result == .mustWait(.seconds(40)))
        #expect(sut.log.value.isEmpty)
        #expect(sut.clock.sleeps.isEmpty)
        #expect(await sut.session.isLocked)
    }

    @Test
    func unlock_thatCantCountTheAttempt_triesNothing() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])
        sut.attemptStorage.failToSave()

        await #expect(throws: LoggingAttemptStorage.Failure.self) {
            try await sut.service.unlock(password: "real")
        }

        #expect(sut.log.value.isEmpty)
        #expect(await sut.session.isLocked)
    }

    /// The count only goes back to zero when a vault opens, so a vault can't open without it.
    @Test
    func unlock_thatCantResetTheCount_staysLocked() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])
        sut.attemptStorage.failToRemove()

        await #expect(throws: LoggingAttemptStorage.Failure.self) {
            try await sut.service.unlock(password: "real")
        }

        #expect(await sut.session.isLocked)
    }
}

// MARK: - The deadline

extension VaultUnlockServiceTests {
    @Test
    func unlock_workWithinTwoThirdsOfTheDeadline_leavesItAlone() async throws {
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [])],
            timings: .init(derivation: .milliseconds(600)),
        )

        _ = try await sut.service.unlock(password: "wrong")

        #expect(sut.deadlineStore.current == deadline)
    }

    /// For example after a restore onto a slower iPhone. The attempt holds to the raised deadline too.
    @Test(arguments: ["real", "wrong"])
    func unlock_derivingAndTryingSlotsForMoreThanTwoThirdsOfTheDeadline_raisesIt(password: String) async throws {
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [])],
            timings: .init(derivation: .milliseconds(1984)),
        )
        let start = sut.clock.now

        _ = try await sut.service.unlock(password: password)

        // 1,984 ms deriving and 16 ms trying slots: 2 s of work that's the same whatever the password.
        #expect(sut.deadlineStore.current == .seconds(3))
        #expect(sut.clock.sleeps == [start.advanced(by: .seconds(3))])
    }

    /// The saved deadline mustn't show how large a vault that opened is: every later attempt, a duress one included,
    /// waits for it.
    @Test
    func unlock_openingAVaultThatDecodesSlowly_doesNotRaiseTheDeadline() async throws {
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [uniqueVaultItem()])],
            timings: .init(body: .seconds(2)),
        )

        #expect(try await sut.service.unlock(password: "real") == .unlocked)

        #expect(sut.deadlineStore.current == deadline)
    }

    @Test
    func unlock_raisesTheDeadlineNoFurtherThanTheMaximum() async throws {
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [])],
            timings: .init(derivation: .seconds(60)),
        )
        let start = sut.clock.now

        _ = try await sut.service.unlock(password: "wrong")

        #expect(sut.deadlineStore.current == VaultUnlockService.maximumDeadline)
        #expect(sut.clock.sleeps == [start.advanced(by: VaultUnlockService.maximumDeadline)])
    }

    @Test
    func unlock_takesAStoredDeadlineBeyondTheMaximumAsTheMaximum() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])
        try await sut.deadlineStore.raiseUnlockDeadline(to: .seconds(600))
        let start = sut.clock.now

        _ = try await sut.service.unlock(password: "wrong")

        #expect(sut.clock.sleeps == [start.advanced(by: VaultUnlockService.maximumDeadline)])
    }

    /// Time the app spends suspended mid-derivation passes on the clock, but isn't work.
    @Test
    func unlock_doesNotCountTimeSuspendedAsWork() async throws {
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [])],
            timings: .init(suspendedDuringDerivation: .seconds(600)),
        )

        _ = try await sut.service.unlock(password: "wrong")

        #expect(sut.deadlineStore.current == deadline)
    }

    /// For example, the AutoFill sheet dismissed mid-derivation.
    @Test
    func unlock_thatIsThrownAway_doesNotRaiseTheDeadline() async throws {
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [])],
            timings: .init(derivation: .seconds(2)),
        )
        sut.work.holdDerivation()
        let attempt = Task { try await sut.service.unlock(password: "real") }
        await sut.work.waitUntilDeriving()

        await sut.service.lock()
        sut.work.releaseDerivation()

        await #expect(throws: CancellationError.self) {
            try await attempt.value
        }
        #expect(sut.deadlineStore.current == deadline)
    }

    @Test
    func unlock_thatCantSaveTheRaisedDeadline_stillHoldsToIt() async throws {
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [])],
            timings: .init(derivation: .seconds(2)),
        )
        sut.deadlineStore.failToRaise()
        let start = sut.clock.now

        let result = try await sut.service.unlock(password: "real")

        #expect(result == .unlocked)
        #expect(sut.deadlineStore.current == deadline)
        #expect(sut.clock.sleeps.count == 1)
        #expect(try #require(sut.clock.sleeps.first) > start.advanced(by: deadline))
    }

    @Test
    func unlock_whoseDerivationFails_throwsAtTheDeadlineWithoutRaisingIt() async throws {
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [])],
            timings: .init(derivation: .seconds(2)),
        )
        sut.work.failDerivation()
        let start = sut.clock.now

        await #expect(throws: SpyUnlockWork.DerivationFailure.self) {
            try await sut.service.unlock(password: "real")
        }

        #expect(sut.clock.sleeps == [start.advanced(by: deadline)])
        #expect(sut.deadlineStore.current == deadline)
        #expect(!sut.log.value.contains("reset the count"))
        #expect(await sut.session.isLocked)
    }
}

// MARK: - Locking

extension VaultUnlockServiceTests {
    @Test
    func lock_locksTheSessionThenPurges() async throws {
        let lockedWhenPurged = SharedMutex([Bool]())
        let sut = try makeSUT(
            vaults: [.init(password: "real", slot: realSlot, items: [uniqueVaultItem()])],
            purge: { session in
                let isLocked = await session.isLocked
                lockedWhenPurged.modify { $0.append(isLocked) }
            },
        )
        _ = try await sut.service.unlock(password: "real")

        await sut.service.lock()

        #expect(lockedWhenPurged.value == [true])
        #expect(await sut.session.isLocked)
        #expect(try await sut.session.retrieve(query: .init()).items == [])
    }

    @Test
    func lock_waitsForAChangeThatIsSavingToFinish() async throws {
        let gate = GatedSlotFileSystem(wrapping: InMemorySlotFileSystem())
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])], fileSystem: gate)
        _ = try await sut.service.unlock(password: "real")
        let events = SharedMutex([String]())

        gate.holdNextWrite()
        let saving = Task {
            try await sut.session.insert(item: uniqueVaultItem().makeWritable())
            events.modify { $0.append("saved") }
        }
        await gate.waitUntilHolding()
        let locking = Task {
            await sut.service.lock()
            events.modify { $0.append("locked") }
        }
        try await Task.sleep(for: .milliseconds(50))
        gate.release()
        try await saving.value
        await locking.value

        #expect(events.value == ["saved", "locked"])
        #expect(try await sut.savedItemCount(inSlot: realSlot, password: "real") == 1)
    }

    /// The lock lands on the session between the attempt's last check and its switch. The switch is conditional on
    /// the session itself, so the lock wins.
    @Test
    func lock_racingTheSwitchToTheVault_wins() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [uniqueVaultItem()])])
        let session = sut.session
        sut.attemptStorage.doWhileRemoving {
            let locked = DispatchSemaphore(value: 0)
            Task.detached {
                await session.lock()
                locked.signal()
            }
            // Bounded, so a starved thread pool fails the test rather than hanging it.
            _ = locked.wait(timeout: .now() + 5)
        }

        await #expect(throws: CancellationError.self) {
            try await sut.service.unlock(password: "real")
        }

        #expect(await sut.session.isLocked)
        #expect(try await sut.session.retrieve(query: .init()).items == [])
    }

    @Test
    func unlock_cancelledWhileWaitingForTheDeadline_throwsTheAttemptAway() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])
        sut.clock.hold()
        let attempt = Task { try await sut.service.unlock(password: "real") }
        await sut.clock.waitUntilHolding()

        attempt.cancel()
        sut.clock.release()

        await #expect(throws: CancellationError.self) {
            try await attempt.value
        }
        #expect(await sut.session.isLocked)
        #expect(!sut.log.value.contains("reset the count"))
    }

    @Test
    func unlock_whileAVaultIsOpen_throwsWithoutCountingAnAttempt() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])
        _ = try await sut.service.unlock(password: "real")
        let steps = sut.log.value.count

        await #expect(throws: VaultUnlockError.notLocked) {
            try await sut.service.unlock(password: "real")
        }

        #expect(sut.log.value.count == steps)
    }

    @Test
    func lock_duringAnAttempt_throwsTheAttemptAway() async throws {
        let sut = try makeSUT(vaults: [.init(password: "real", slot: realSlot, items: [])])
        sut.clock.hold()
        let attempt = Task { try await sut.service.unlock(password: "real") }
        await sut.clock.waitUntilHolding()

        await sut.service.lock()
        sut.clock.release()

        await #expect(throws: CancellationError.self) {
            try await attempt.value
        }
        #expect(await sut.session.isLocked)
        #expect(!sut.log.value.contains("reset the count"))
    }
}

// MARK: - Memory

extension VaultUnlockServiceTests {
    @Test
    func hasMemoryHeadroomToUnlock_needsTheDerivationTheFileAndAMargin() async throws {
        let needed = Int(EncryptedVaultFixture.kdfParameters.memoryKiB) * 1024 + (128 + 16 * (1 << 20)) + (16 << 20)

        // No figure means no limit, as in the simulator. On an iPhone, 0 means the process is over its limit.
        for (available, expected) in [(needed, true), (needed - 1, false), (0, false), (nil, true)] {
            let sut = try makeSUT(vaults: [], availableMemory: available)
            #expect(try await sut.service.hasMemoryHeadroomToUnlock() == expected, "\(String(describing: available))")
        }
    }

    @Test
    func hasMemoryHeadroomToUnlock_readsOnlyTheHeader() async throws {
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: InMemorySlotFileSystem())
        let sut = try makeSUT(vaults: [], fileSystem: fileSystem, availableMemory: 0)
        let steps = fileSystem.log.count

        _ = try await sut.service.hasMemoryHeadroomToUnlock()

        #expect(Array(fileSystem.log.dropFirst(steps)) == ["read the start of vault-slots.v1"])
    }

    @Test
    func hasMemoryHeadroomToUnlock_withoutAVaultFile_throws() async throws {
        let sut = try makeSUT(vaults: [])
        try sut.fileSystem.removeItem(at: sut.file.url)

        await #expect(throws: VaultUnlockError.noEncryptedVault) {
            try await sut.service.hasMemoryHeadroomToUnlock()
        }
    }
}

// MARK: - Helpers

extension VaultUnlockServiceTests {
    struct TestVault {
        var password: String
        var slot: Int
        var items: [VaultItem]
        var wrappedAt = Date(timeIntervalSince1970: 1_790_000_000)
    }

    struct SUT {
        let service: VaultUnlockService
        let session: VaultStoreSession
        let file: EncryptedVaultFile
        let fileSystem: any SlotFileSystem
        let clock: ManualUnlockClock
        let work: SpyUnlockWork
        /// Where the real attempt counter keeps its count, and the clock it times delays with.
        let attemptStorage: LoggingAttemptStorage
        let attemptClock: FakeAppLockClock
        let deadlineStore: FakeUnlockDeadlineStore
        /// What the counter and the work did, in order.
        let log: SharedMutex<[String]>

        /// Flips a byte in the middle of the slot's body.
        func damageBody(ofSlot index: Int) async throws {
            var contents = try #require(try await file.open())
            var bytes = contents.bytes
            bytes[contents.slotRange(index).lowerBound + 1000] ^= 0x01
            contents = try VaultSlotFile(bytes: bytes)
            try await file.withLock { [contents] in try $0.write(contents) { _ in } }
        }

        func savedItemCount(inSlot index: Int, password: String) async throws -> Int {
            let contents = try #require(try await file.open())
            let key = try contents.header.passwordKey(for: password)
            let slot = try contents.openSlot(index, with: key)
            return try EncryptedVaultPayload.decode(slot: slot, in: contents).items.count
        }
    }

    /// A file with the given vaults and every other slot random, and a service to unlock it, starting locked.
    private func makeSUT(
        vaults: [TestVault],
        fileSystem: any SlotFileSystem = InMemorySlotFileSystem(),
        timings: SpyUnlockWork.Timings = .init(),
        availableMemory: Int? = nil,
        purge: @escaping @Sendable (VaultStoreSession) async -> Void = { _ in },
    ) throws -> SUT {
        var contents = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
        for vault in vaults {
            try contents.createVault(
                inSlot: vault.slot,
                rootKey: contents.header.passwordKey(for: vault.password),
                payload: EncryptedVaultPayload.encode(EncryptedVaultStoreTests.state(items: vault.items)),
                wrappedAt: vault.wrappedAt,
            )
        }
        let file = EncryptedVaultFile(directory: EncryptedVaultFixture.inMemoryDirectory, fileSystem: fileSystem)
        try fileSystem.createFile(at: file.url, contents: contents.bytes)

        let session = VaultStoreSession(target: .locked)
        let clock = ManualUnlockClock()
        let log = SharedMutex([String]())
        let attemptStorage = LoggingAttemptStorage(log: log)
        let attemptClock = FakeAppLockClock()
        let deadlineStore = FakeUnlockDeadlineStore(deadline: deadline)
        let work = SpyUnlockWork(log: log, clock: clock, timings: timings)
        let service = VaultUnlockService(
            file: file,
            session: session,
            attemptCounter: AppLockPasswordAttemptCounter(storage: attemptStorage, clock: attemptClock),
            deadlineStore: deadlineStore,
            purgeVaultContents: { await purge(session) },
            clock: clock,
            work: work,
            availableMemory: { availableMemory },
        )
        return SUT(
            service: service,
            session: session,
            file: file,
            fileSystem: fileSystem,
            clock: clock,
            work: work,
            attemptStorage: attemptStorage,
            attemptClock: attemptClock,
            deadlineStore: deadlineStore,
            log: log,
        )
    }
}

/// Wraps a file system, and can hold the next file written until the test lets it go.
final class GatedSlotFileSystem: SlotFileSystem {
    private let base: any SlotFileSystem
    private let holdsNextWrite = SharedMutex(false)
    private let isHolding = SharedMutex(false)
    private let gate = DispatchSemaphore(value: 0)

    init(wrapping base: any SlotFileSystem) {
        self.base = base
    }

    func holdNextWrite() {
        holdsNextWrite.modify { $0 = true }
    }

    func release() {
        gate.signal()
    }

    /// Waits (for up to 5 seconds) until a write is being held.
    func waitUntilHolding() async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !isHolding.value, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func createFile(at url: URL, contents: Data, protection: SlotFileProtection) throws {
        let holds = holdsNextWrite.modify { holds in
            defer { holds = false }
            return holds
        }
        if holds {
            isHolding.modify { $0 = true }
            _ = gate.wait(timeout: .now() + 5)
        }
        try base.createFile(at: url, contents: contents, protection: protection)
    }

    func tryLock(_ url: URL) throws -> SlotFileLock? {
        try base.tryLock(url)
    }

    func unlock(_ lock: SlotFileLock) {
        base.unlock(lock)
    }

    func contents(of url: URL) throws -> Data? {
        try base.contents(of: url)
    }

    func prefix(of url: URL, length: Int) throws -> (bytes: Data, fileSize: Int)? {
        try base.prefix(of: url, length: length)
    }

    func fileSize(of url: URL) throws -> Int? {
        try base.fileSize(of: url)
    }

    func synchronizeFile(at url: URL) throws {
        try base.synchronizeFile(at: url)
    }

    func moveItem(at source: URL, replacing destination: URL) throws {
        try base.moveItem(at: source, replacing: destination)
    }

    func synchronizeDirectory(at url: URL) throws {
        try base.synchronizeDirectory(at: url)
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try base.contentsOfDirectory(at: url)
    }
}
