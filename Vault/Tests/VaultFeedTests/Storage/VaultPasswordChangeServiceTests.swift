import CryptoKit
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// Changing the App Lock Password, turning it off and back on, and recovering from a change the app stopped in the
/// middle of.
///
/// Each test has a file with a real vault (password "real") and a duress vault (password "duress"), and every other
/// slot random. The session starts with one of them open.
struct VaultPasswordChangeServiceTests {
    private static let realSlot = 4
    private static let duressSlot = 11
    private static let deadline = Duration.seconds(1)
    /// When both vaults were made.
    private static let longAgo = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Changing the password

    @Test
    func changePassword_withTheCurrentPassword_movesTheVaultToTheNewPassword() async throws {
        let sut = try await makeSUT()

        let result = try await sut.service.changePassword(current: "real", new: "new")

        #expect(result == .changed)
        #expect(try sut.slots(openedBy: "new") == [Self.realSlot])
        #expect(try sut.slots(openedBy: "real").isEmpty)
        #expect(try sut.savedState(inSlot: Self.realSlot, with: sut.passwordKey("new")) == sut.realState)
        #expect(try sut.stateFile.read() == VaultStorageState(mode: .password, unlockDeadline: Self.deadline))
        #expect(sut.base.protection(of: sut.fileURL) == .complete)
    }

    @Test
    func changePassword_afterwards_theNewPasswordUnlocksAndTheOldIsWrong() async throws {
        let sut = try await makeSUT()
        _ = try await sut.service.changePassword(current: "real", new: "new")

        await sut.unlockService.lock()
        #expect(try await sut.unlockService.unlock(password: "real") == .wrongPassword)
        #expect(try await sut.unlockService.unlock(password: "new") == .unlocked)
        #expect(try await sut.session.retrieve(query: .init()).items == [sut.realItem])
    }

    /// The store the session has open keeps working: it saves under the new key.
    @Test
    func changePassword_leavesTheVaultOpenAndSavingUnderTheNewKey() async throws {
        let sut = try await makeSUT()
        _ = try await sut.service.changePassword(current: "real", new: "new")

        let added = try await sut.session.insert(item: uniqueVaultItem().makeWritable())

        let saved = try sut.savedState(inSlot: Self.realSlot, with: sut.passwordKey("new"))
        #expect(saved.items.map(\.id).contains(added.rawValue))
        #expect(await !sut.session.isLocked)
    }

    /// A new data key and body: an older copy of the file, with the old password, can't read the new body, and the
    /// old key box can't be put back to open it.
    @Test
    func changePassword_rotatesTheVaultsDataKey() async throws {
        let sut = try await makeSUT()
        let before = try sut.contents()
        let oldKey = try sut.passwordKey("real")
        let oldSlot = try before.openSlot(Self.realSlot, with: oldKey)

        _ = try await sut.service.changePassword(current: "real", new: "new")

        let after = try sut.contents()
        let newSlot = try after.openSlot(Self.realSlot, with: sut.passwordKey("new"))
        #expect(Self.bytes(of: newSlot.dataKey) != Self.bytes(of: oldSlot.dataKey))
        let body = Self.body(of: Self.realSlot, in: after)
        #expect(after.bytes[body] != before.bytes[body])
        #expect(throws: VaultSlotFileError.bodyDidNotOpen) {
            try after.openPayload(of: oldSlot)
        }
        var spliced = after.bytes
        let keyBox = Self.keyBox(of: Self.realSlot, in: after)
        spliced.replaceSubrange(keyBox, with: before.bytes[keyBox])
        let splicedFile = try VaultSlotFile(bytes: spliced)
        #expect(throws: VaultSlotFileError.bodyDidNotOpen) {
            try splicedFile.openPayload(of: splicedFile.openSlot(Self.realSlot, with: oldKey))
        }
    }

    @Test
    func changePassword_leavesTheHeaderAndEveryOtherSlotByteForByte() async throws {
        let sut = try await makeSUT()
        let before = try sut.contents()

        _ = try await sut.service.changePassword(current: "real", new: "new")

        try Self.expectOnlySlotChanged(Self.realSlot, from: before, to: sut.contents())
        #expect(try sut.slots(openedBy: "duress") == [Self.duressSlot])
    }

    /// From a duress vault, it behaves exactly as from the real one, and changes only the duress vault's slot.
    @Test
    func changePassword_fromADuressVault_changesOnlyItsSlot() async throws {
        let sut = try await makeSUT(openedWith: "duress")
        let before = try sut.contents()

        let result = try await sut.service.changePassword(current: "duress", new: "new")

        #expect(result == .changed)
        try Self.expectOnlySlotChanged(Self.duressSlot, from: before, to: sut.contents())
        #expect(try sut.slots(openedBy: "new") == [Self.duressSlot])
        #expect(try sut.slots(openedBy: "real") == [Self.realSlot])
        #expect(try sut.savedState(inSlot: Self.duressSlot, with: sut.passwordKey("new")) == sut.duressState)
    }

    /// The check is an unlock attempt: counted first, held to the deadline, and the count reset only if it's
    /// right.
    @Test
    func changePassword_checksTheCurrentPasswordAsAnAttempt() async throws {
        let sut = try await makeSUT()
        sut.log.modify { $0.removeAll() }
        let start = sut.clock.now

        _ = try await sut.service.changePassword(current: "real", new: "new")

        let log = sut.log.value
        #expect(log.first == "count the attempt")
        #expect(log.dropFirst().first == "derive")
        #expect(log.last == "reset the count")
        #expect(!log.contains("open a body"))
        #expect(sut.clock.sleeps.last == start.advanced(by: Self.deadline))
    }

    @Test
    func changePassword_withAWrongPassword_isWrongAndChangesNothing() async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()
        sut.log.modify { $0.removeAll() }

        let result = try await sut.service.changePassword(current: "wrong", new: "new")

        #expect(result == .wrongPassword)
        #expect(try sut.bytes() == before)
        #expect(sut.log.value.first == "count the attempt")
        #expect(!sut.log.value.contains("reset the count"))
    }

    /// The duress password opens a vault, but not the open one: it's as wrong as any other, so this never shows the
    /// duress vault is there.
    @Test
    func changePassword_withAnotherVaultsPassword_isWrongAndChangesNothing() async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()
        sut.log.modify { $0.removeAll() }

        let result = try await sut.service.changePassword(current: "duress", new: "new")

        #expect(result == .wrongPassword)
        #expect(try sut.bytes() == before)
        #expect(!sut.log.value.contains("reset the count"))
    }

    @Test
    func changePassword_whileTheUserMustWait_triesNothing() async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()
        sut.log.modify { $0.removeAll() }
        sut.attemptStorage.setRecord(count: 5, latestAt: sut.attemptClock.now)
        sut.attemptClock.advance(by: .seconds(20))

        let result = try await sut.service.changePassword(current: "real", new: "new")

        #expect(result == .mustWait(.seconds(40)))
        #expect(sut.log.value.isEmpty)
        #expect(try sut.bytes() == before)
    }

    @Test(arguments: [("real", "real"), ("\u{E9}t\u{E9}", "e\u{301}te\u{301}")])
    func changePassword_toTheSamePassword_throwsBeforeTryingAnything(current: String, new: String) async throws {
        let sut = try await makeSUT(password: current)
        sut.log.modify { $0.removeAll() }

        await #expect(throws: VaultPasswordChangeError.newPasswordMatchesCurrent) {
            try await sut.service.changePassword(current: current, new: new)
        }

        #expect(sut.log.value.isEmpty)
    }

    /// Only the user knows whether the new password opens another vault, so it's accepted without a word. It opens
    /// the vault it was just set for, the most recently wrapped (see "Same passwords" in the design).
    @Test
    func changePassword_toAPasswordThatOpensAnotherVault_isAccepted() async throws {
        let sut = try await makeSUT()

        let result = try await sut.service.changePassword(current: "real", new: "duress")

        #expect(result == .changed)
        #expect(try sut.slots(openedBy: "duress") == [Self.realSlot, Self.duressSlot])
        await sut.unlockService.lock()
        #expect(try await sut.unlockService.unlock(password: "duress") == .unlocked)
        #expect(try await sut.session.retrieve(query: .init()).items == [sut.realItem])
    }

    /// The key is derived from the composed form, so a password typed either way opens the vault.
    @Test
    func changePassword_derivesTheNewKeyFromTheComposedForm() async throws {
        let sut = try await makeSUT()

        _ = try await sut.service.changePassword(current: "real", new: "e\u{301}te\u{301}")

        await sut.unlockService.lock()
        #expect(try await sut.unlockService.unlock(password: "\u{E9}t\u{E9}") == .unlocked)
    }

    @Test
    func changePassword_withThePasswordOff_throws() async throws {
        let sut = try await makeSUT(mode: .deviceKey)

        await #expect(throws: VaultPasswordChangeError.passwordIsNotOn) {
            try await sut.service.changePassword(current: "real", new: "new")
        }
    }

    @Test
    func changePassword_withNoVaultOpen_throws() async throws {
        let sut = try await makeSUT()
        await sut.unlockService.lock()

        await #expect(throws: VaultPasswordChangeError.noOpenVault) {
            try await sut.service.changePassword(current: "real", new: "new")
        }
    }

    @Test
    func changePassword_whileAnotherChangeIsUnderway_throws() async throws {
        let sut = try await makeSUT()
        sut.clock.hold()
        let first = Task { try await sut.service.changePassword(current: "real", new: "new") }
        await sut.clock.waitUntilHolding()

        await #expect(throws: VaultPasswordChangeError.changeUnderway) {
            try await sut.service.turnOffPassword(current: "real")
        }

        sut.clock.release()
        #expect(try await first.value == .changed)
    }

    /// Locking while the current password is checked throws the check away, as it does an unlock attempt.
    @Test
    func changePassword_lockedWhileChecking_changesNothing() async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()
        sut.clock.hold()
        let change = Task { try await sut.service.changePassword(current: "real", new: "new") }
        await sut.clock.waitUntilHolding()

        await sut.unlockService.lock()
        sut.clock.release()

        await #expect(throws: CancellationError.self) {
            try await change.value
        }
        #expect(try sut.bytes() == before)
    }
}

// MARK: - Turning the password off

extension VaultPasswordChangeServiceTests {
    @Test
    func turnOffPassword_wrapsTheVaultWithANewDeviceKey() async throws {
        let sut = try await makeSUT()
        let before = try sut.contents()

        let result = try await sut.service.turnOffPassword(current: "real")

        #expect(result == .changed)
        let deviceKey = try #require(sut.deviceKeyStore.key)
        #expect(try sut.slots(openedBy: .device(deviceKey)) == [Self.realSlot])
        #expect(try sut.slots(openedBy: "real").isEmpty)
        #expect(try sut.savedState(inSlot: Self.realSlot, with: .device(deviceKey)) == sut.realState)
        #expect(try sut.stateFile.read() == VaultStorageState(mode: .deviceKey, unlockDeadline: Self.deadline))
        try Self.expectOnlySlotChanged(Self.realSlot, from: before, to: sut.contents())
        let oldSlot = try before.openSlot(Self.realSlot, with: sut.passwordKey("real"))
        let newSlot = try sut.contents().openSlot(Self.realSlot, with: .device(deviceKey))
        #expect(Self.bytes(of: newSlot.dataKey) != Self.bytes(of: oldSlot.dataKey))
    }

    /// Readable after the first unlock, like the plain store, so the widgets can read it while the device is locked.
    @Test
    func turnOffPassword_makesTheFileReadableAfterTheFirstUnlock() async throws {
        let sut = try await makeSUT()

        _ = try await sut.service.turnOffPassword(current: "real")

        #expect(sut.base.protection(of: sut.fileURL) == .completeUntilFirstUserAuthentication)
    }

    @Test
    func turnOffPassword_replacesAnyDeviceKeyThereWas() async throws {
        let stale = SymmetricKey(size: .bits256)
        let sut = try await makeSUT(deviceKey: stale)

        _ = try await sut.service.turnOffPassword(current: "real")

        let deviceKey = try #require(sut.deviceKeyStore.key)
        #expect(Self.bytes(of: deviceKey) != Self.bytes(of: stale))
        #expect(try sut.slots(openedBy: .device(stale)).isEmpty)
    }

    @Test
    func turnOffPassword_fromADuressVault_changesOnlyItsSlot() async throws {
        let sut = try await makeSUT(openedWith: "duress")
        let before = try sut.contents()

        _ = try await sut.service.turnOffPassword(current: "duress")

        let deviceKey = try #require(sut.deviceKeyStore.key)
        try Self.expectOnlySlotChanged(Self.duressSlot, from: before, to: sut.contents())
        #expect(try sut.slots(openedBy: .device(deviceKey)) == [Self.duressSlot])
        #expect(try sut.slots(openedBy: "real") == [Self.realSlot])
    }

    @Test(arguments: ["wrong", "duress"])
    func turnOffPassword_withAPasswordThatIsNotTheOpenVaults_isWrongAndChangesNothing(password: String) async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()

        let result = try await sut.service.turnOffPassword(current: password)

        #expect(result == .wrongPassword)
        #expect(try sut.bytes() == before)
        #expect(sut.deviceKeyStore.key == nil)
        #expect(try sut.stateFile.read().mode == .password)
    }

    @Test
    func turnOffPassword_whileTheUserMustWait_triesNothing() async throws {
        let sut = try await makeSUT()
        sut.attemptStorage.setRecord(count: 5, latestAt: sut.attemptClock.now)

        let result = try await sut.service.turnOffPassword(current: "real")

        #expect(result == .mustWait(.seconds(60)))
        #expect(sut.deviceKeyStore.key == nil)
    }

    @Test
    func turnOffPassword_thatCantMakeADeviceKey_changesNothing() async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()
        sut.deviceKeyStore.failToMake()

        await #expect(throws: InMemoryDeviceKeyStore.Failure.self) {
            try await sut.service.turnOffPassword(current: "real")
        }

        #expect(try sut.bytes() == before)
        #expect(try sut.stateFile.read() == VaultStorageState(mode: .password, unlockDeadline: Self.deadline))
    }

    /// An unlock attempt elsewhere can raise the deadline while the password is checked. The new mode is written
    /// on top of that, not over it.
    @Test
    func turnOffPassword_keepsAnUnlockDeadlineRaisedMeanwhile() async throws {
        let sut = try await makeSUT()
        sut.attemptStorage.doWhileRemoving { [stateFile = sut.stateFile] in
            try? stateFile.write(VaultStorageState(mode: .password, unlockDeadline: .seconds(3)))
        }

        _ = try await sut.service.turnOffPassword(current: "real")

        #expect(try sut.stateFile.read() == VaultStorageState(mode: .deviceKey, unlockDeadline: .seconds(3)))
    }

    @Test
    func turnOffPassword_thatIsOffAlready_throws() async throws {
        let sut = try await makeSUT(mode: .deviceKey)

        await #expect(throws: VaultPasswordChangeError.passwordIsNotOn) {
            try await sut.service.turnOffPassword(current: "real")
        }
    }
}

// MARK: - Turning the password back on

extension VaultPasswordChangeServiceTests {
    @Test
    func turnOnPassword_wrapsTheVaultWithTheNewPasswordAndDeletesTheDeviceKey() async throws {
        let sut = try await makeSUT(mode: .deviceKey)
        let deviceKey = try #require(sut.deviceKeyStore.key)
        let before = try sut.contents()

        try await sut.service.turnOnPassword("new")

        #expect(try sut.slots(openedBy: "new") == [Self.realSlot])
        #expect(try sut.slots(openedBy: .device(deviceKey)).isEmpty)
        #expect(sut.deviceKeyStore.key == nil)
        #expect(try sut.savedState(inSlot: Self.realSlot, with: sut.passwordKey("new")) == sut.realState)
        #expect(try sut.stateFile.read() == VaultStorageState(mode: .password, unlockDeadline: Self.deadline))
        #expect(sut.base.protection(of: sut.fileURL) == .complete)
        try Self.expectOnlySlotChanged(Self.realSlot, from: before, to: sut.contents())
        let oldSlot = try before.openSlot(Self.realSlot, with: .device(deviceKey))
        let newSlot = try sut.contents().openSlot(Self.realSlot, with: sut.passwordKey("new"))
        #expect(Self.bytes(of: newSlot.dataKey) != Self.bytes(of: oldSlot.dataKey))
    }

    /// The same salt: the file's header, and so every other slot, stays as it was.
    @Test
    func turnOnPassword_keepsTheFilesSalt() async throws {
        let sut = try await makeSUT(mode: .deviceKey)
        let before = try sut.contents()

        try await sut.service.turnOnPassword("new")

        #expect(try sut.contents().header.salt == before.header.salt)
    }

    @Test
    func turnOnPassword_resetsTheCountFirst() async throws {
        let sut = try await makeSUT(mode: .deviceKey)
        sut.attemptStorage.setRecord(count: 3, latestAt: sut.attemptClock.now)
        sut.log.modify { $0.removeAll() }

        try await sut.service.turnOnPassword("new")

        #expect(sut.log.value == ["reset the count"])
        #expect(try sut.attemptStorage.load() == nil)
    }

    @Test
    func turnOnPassword_afterwards_theNewPasswordUnlocksAndTheDeviceKeyDoesNot() async throws {
        let sut = try await makeSUT(mode: .deviceKey)
        try await sut.service.turnOnPassword("new")

        await sut.unlockService.lock()
        await #expect(throws: VaultUnlockError.noDeviceKey) {
            try await sut.unlockService.unlockWithDeviceKey()
        }
        #expect(try await sut.unlockService.unlock(password: "new") == .unlocked)
        #expect(try await sut.session.retrieve(query: .init()).items == [sut.realItem])
    }

    /// The device key opens nothing any more, so failing to delete it is no reason to fail.
    @Test
    func turnOnPassword_thatCantDeleteTheDeviceKey_stillTurnsItOn() async throws {
        let sut = try await makeSUT(mode: .deviceKey)
        let deviceKey = try #require(sut.deviceKeyStore.key)
        sut.deviceKeyStore.failToRemove()

        try await sut.service.turnOnPassword("new")

        #expect(try sut.stateFile.read().mode == .password)
        #expect(try sut.slots(openedBy: .device(deviceKey)).isEmpty)
    }

    @Test
    func turnOnPassword_thatIsOnAlready_throws() async throws {
        let sut = try await makeSUT()

        await #expect(throws: VaultPasswordChangeError.passwordIsNotOff) {
            try await sut.service.turnOnPassword("new")
        }
    }

    /// Off and back on from a duress vault: the real vault's slot, and its password, never change.
    @Test
    func turnOffThenOn_fromADuressVault_neverTouchesTheRealVault() async throws {
        let sut = try await makeSUT(openedWith: "duress")
        let before = try sut.contents()

        _ = try await sut.service.turnOffPassword(current: "duress")
        try await sut.service.turnOnPassword("new")

        try Self.expectOnlySlotChanged(Self.duressSlot, from: before, to: sut.contents())
        #expect(try sut.slots(openedBy: "real") == [Self.realSlot])
        #expect(try sut.slots(openedBy: "new") == [Self.duressSlot])
    }
}

// MARK: - Unlocking with the device key

extension VaultPasswordChangeServiceTests {
    /// Device authentication, which the app lock asks for first, is all it takes: no password, no attempt counted,
    /// and no deadline. It works while the device is locked, as the widgets need.
    @Test
    func unlockWithDeviceKey_opensTheVaultWithoutAnAttemptOrADeadline() async throws {
        let sut = try await makeSUT()
        _ = try await sut.service.turnOffPassword(current: "real")
        await sut.unlockService.lock()
        sut.log.modify { $0.removeAll() }
        let sleeps = sut.clock.sleeps
        sut.base.isDeviceLocked = true

        try await sut.unlockService.unlockWithDeviceKey()

        #expect(try await sut.session.retrieve(query: .init()).items == [sut.realItem])
        #expect(sut.log.value.isEmpty)
        #expect(sut.clock.sleeps == sleeps)
    }

    /// With the password on, the file can't be read while the device is locked.
    @Test
    func unlock_withThePasswordOn_needsTheDeviceUnlocked() async throws {
        let sut = try await makeSUT()
        await sut.unlockService.lock()
        sut.base.isDeviceLocked = true

        await #expect(throws: CocoaError.self) {
            try await sut.unlockService.unlock(password: "real")
        }
    }

    @Test
    func unlock_withThePasswordOff_thePasswordOpensNothing() async throws {
        let sut = try await makeSUT()
        _ = try await sut.service.turnOffPassword(current: "real")
        await sut.unlockService.lock()

        #expect(try await sut.unlockService.unlock(password: "real") == .wrongPassword)
    }

    @Test
    func unlockWithDeviceKey_withoutADeviceKey_throws() async throws {
        let sut = try await makeSUT()
        await sut.unlockService.lock()

        await #expect(throws: VaultUnlockError.noDeviceKey) {
            try await sut.unlockService.unlockWithDeviceKey()
        }
        #expect(await sut.session.isLocked)
    }

    @Test
    func unlockWithDeviceKey_withADeviceKeyThatOpensNothing_throws() async throws {
        let sut = try await makeSUT(deviceKey: SymmetricKey(size: .bits256))
        await sut.unlockService.lock()

        await #expect(throws: VaultUnlockError.deviceKeyOpensNoVault) {
            try await sut.unlockService.unlockWithDeviceKey()
        }
        #expect(await sut.session.isLocked)
    }

    @Test
    func unlockWithDeviceKey_whileAVaultIsOpen_throws() async throws {
        let sut = try await makeSUT(mode: .deviceKey)

        await #expect(throws: VaultUnlockError.notLocked) {
            try await sut.unlockService.unlockWithDeviceKey()
        }
    }
}

// MARK: - Stopping at any step

extension VaultPasswordChangeServiceTests {
    enum Operation: String, CaseIterable, CustomTestStringConvertible {
        case change
        case turnOff
        case turnOn

        var testDescription: String {
            rawValue
        }

        var startMode: VaultStorageState.Mode {
            self == .turnOn ? .deviceKey : .password
        }

        func run(on sut: SUT) async throws {
            switch self {
            case .change: _ = try await sut.service.changePassword(current: "real", new: "new")
            case .turnOff: _ = try await sut.service.turnOffPassword(current: "real")
            case .turnOn: try await sut.service.turnOnPassword("new")
            }
        }
    }

    /// The app stops at any step. At the next launch, the vault is intact and wrapped with the key the mode says:
    /// either the one it had or the new one, never neither. Nothing else in the file has changed.
    @Test(arguments: Operation.allCases)
    func operation_stoppedAtAnyStep_recoversAtLaunch(operation: Operation) async throws {
        let steps = try await Self.stepCount(of: operation)
        #expect(steps > 5)

        for step in 1 ... steps {
            let sut = try await makeSUT(mode: operation.startMode)
            let before = try sut.contents()
            sut.fileSystem.inject(.crash(atStep: step))

            _ = try? await operation.run(on: sut)

            try await expectRecoveredAtLaunch(sut, after: operation, before: before, context: "crash at step \(step)")
        }
    }

    /// One step fails. Whatever the change does about it, the next launch finds the vault intact and consistent.
    @Test(arguments: Operation.allCases)
    func operation_failingAtAnyStep_recoversAtLaunch(operation: Operation) async throws {
        let steps = try await Self.stepCount(of: operation)

        for step in 1 ... steps {
            let sut = try await makeSUT(mode: operation.startMode)
            let before = try sut.contents()
            sut.fileSystem.inject(.fail(atStep: step))

            _ = try? await operation.run(on: sut)

            try await expectRecoveredAtLaunch(sut, after: operation, before: before, context: "failure at step \(step)")
        }
    }

    /// A failure before the rename leaves the file as it was, and clears the journal straight away: the app can go
    /// on without relaunching.
    @Test(arguments: [Operation.turnOff, .turnOn])
    func operation_failingToWriteTheFile_leavesTheModeAsItWas(operation: Operation) async throws {
        let createTemp = try await Self.stepNumber(of: "create temp", in: operation)
        let sut = try await makeSUT(mode: operation.startMode)
        let before = try sut.bytes()
        let stateBefore = try sut.stateFile.read()
        sut.fileSystem.inject(.fail(atStep: createTemp))

        await #expect(throws: FaultInjectingSlotFileSystem.InjectedFault.self) {
            try await operation.run(on: sut)
        }

        #expect(try sut.bytes() == before)
        #expect(try sut.stateFile.read() == stateBefore)
    }

    /// Runs the operation without faults, and counts its file system steps.
    private static func stepCount(of operation: Operation) async throws -> Int {
        try await steps(of: operation).count
    }

    /// The number of the operation's first step with this name.
    private static func stepNumber(of name: String, in operation: Operation) async throws -> Int {
        try await #require(steps(of: operation).firstIndex(of: name)) + 1
    }

    /// Runs the operation without faults, and names its file system steps, in order.
    private static func steps(of operation: Operation) async throws -> [String] {
        let sut = try await makeSUT(mode: operation.startMode)
        sut.fileSystem.inject(.fail(atSteps: []))
        let before = sut.fileSystem.log.count
        try await operation.run(on: sut)
        return sut.fileSystem.log.dropFirst(before).filter { $0 != "unlock" }
    }

    private func expectRecoveredAtLaunch(
        _ sut: SUT,
        after operation: Operation,
        before: VaultSlotFile,
        context: String,
    ) async throws {
        let comment = Comment(rawValue: context)
        let mode = try sut.relaunch()
        let after = try #require(try await EncryptedVaultFile(directory: sut.directory, fileSystem: sut.base).open())
        #expect(try sut.stateFile.read().transition == nil, comment)
        #expect(try sut.temporaryFileNames().isEmpty, comment)
        try Self.expectOnlySlotChanged(Self.realSlot, from: before, to: after)

        let deviceKey = sut.deviceKeyStore.key.map(VaultSlotRootKey.device)
        let expectedKey: VaultSlotRootKey?
        switch (operation, mode) {
        case (.change, .password):
            let opening = try ["real", "new"].filter { try sut.slots(openedBy: $0, in: after) == [Self.realSlot] }
            #expect(opening.count == 1, comment)
            expectedKey = try opening.first.map { try sut.passwordKey($0) }
        case (.turnOff, .password):
            expectedKey = try sut.passwordKey("real")
        case (.turnOn, .password):
            // Nothing the device key opened is left, and neither is the key.
            #expect(sut.deviceKeyStore.key == nil, comment)
            expectedKey = try sut.passwordKey("new")
        case (.turnOff, .deviceKey), (.turnOn, .deviceKey):
            #expect(try sut.slots(openedBy: operation == .turnOff ? "real" : "new", in: after).isEmpty, comment)
            expectedKey = deviceKey
        default:
            Issue.record("\(context): \(operation) ended in the \(mode) mode")
            expectedKey = nil
        }
        let key = try #require(expectedKey, comment)
        let slot = try after.openSlot(Self.realSlot, with: key)
        #expect(try EncryptedVaultPayload.decode(slot: slot, in: after) == sut.realState, comment)
        if mode == .password, let deviceKey {
            #expect(try sut.slots(openedBy: deviceKey, in: after).isEmpty, comment)
        }
    }
}

// MARK: - Wrap times

extension VaultPasswordChangeServiceTests {
    /// The wrap time breaks ties when a password opens more than one slot, so it comes from the stamper, given the
    /// slot's own wrap time, never from the clock directly.
    @Test(arguments: Operation.allCases)
    func operation_takesTheWrapTimeFromTheStamper(operation: Operation) async throws {
        let stamp = Date(timeIntervalSince1970: 1_750_000_000.5)
        let stamper = SpyWrapStamper(stamp: stamp)
        let sut = try await makeSUT(mode: operation.startMode, wrapStamper: stamper)

        try await operation.run(on: sut)

        let key: VaultSlotRootKey = if operation == .turnOff {
            try .device(#require(sut.deviceKeyStore.key))
        } else {
            try sut.passwordKey("new")
        }
        #expect(stamper.previousStamps == [Self.longAgo])
        #expect(try sut.contents().openSlot(Self.realSlot, with: key).wrappedAt == stamp)
    }

    @Test
    func operation_thatCantStampTheWrap_changesNothing() async throws {
        let sut = try await makeSUT(wrapStamper: SpyWrapStamper(stamp: nil))
        let before = try sut.bytes()

        await #expect(throws: SpyWrapStamper.Failure.self) {
            try await sut.service.changePassword(current: "real", new: "new")
        }

        #expect(try sut.bytes() == before)
    }

    @Test
    func wallClockWrapStamper_isTheClock_butAlwaysAfterTheSlotsOwnWrap() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sut = VaultWallClockWrapStamper(now: { now })

        #expect(sut.nextWrapStamp(rewrapping: now.addingTimeInterval(-60)) == now)
        #expect(sut.nextWrapStamp(rewrapping: now) == now.addingTimeInterval(0.001))
        #expect(sut.nextWrapStamp(rewrapping: now.addingTimeInterval(60)) == now.addingTimeInterval(60.001))
    }

    /// Returns `stamp` for every wrap, or fails if it's `nil`, and records the wrap time it was given.
    final class SpyWrapStamper: VaultWrapStamping {
        struct Failure: Error {}

        private let stamp: Date?
        private let previous = SharedMutex([Date]())

        init(stamp: Date?) {
            self.stamp = stamp
        }

        var previousStamps: [Date] {
            previous.value
        }

        func nextWrapStamp(rewrapping previous: Date) throws -> Date {
            self.previous.modify { $0.append(previous) }
            guard let stamp else { throw Failure() }
            return stamp
        }
    }
}

// MARK: - Background time

extension VaultPasswordChangeServiceTests {
    /// Rekeying holds `vault-slots.lock`, so every file step happens with background time asked for.
    @Test(arguments: Operation.allCases)
    func operation_runsEveryStepWithBackgroundTime(operation: Operation) async throws {
        let steps = SharedMutex([String]())
        let sut = try await makeSUT(mode: operation.startMode, backgroundTime: { fileSystem in
            VaultBackgroundTime {
                steps.modify { $0.append("begin at step \(fileSystem.log.count)") }
                return { steps.modify { $0.append("end at step \(fileSystem.log.count)") } }
            }
        })
        let first = sut.fileSystem.log.count

        try await operation.run(on: sut)

        #expect(steps.value == ["begin at step \(first)", "end at step \(sut.fileSystem.log.count)"])
    }

    @Test
    func operation_thatThrows_stillGivesTheBackgroundTimeBack() async throws {
        let ended = SharedMutex(false)
        let sut = try await makeSUT(backgroundTime: { _ in
            VaultBackgroundTime { { ended.modify { $0 = true } } }
        })

        await #expect(throws: VaultPasswordChangeError.newPasswordMatchesCurrent) {
            try await sut.service.changePassword(current: "real", new: "real")
        }

        #expect(ended.value)
    }
}

// MARK: - Helpers

extension VaultPasswordChangeServiceTests {
    struct SUT {
        let service: VaultPasswordChangeService
        let unlockService: VaultUnlockService
        let session: VaultStoreSession
        /// Everything the services do to files goes through this.
        let fileSystem: FaultInjectingSlotFileSystem
        /// The files themselves, for the test to look at without taking a step.
        let base: InMemorySlotFileSystem
        let deviceKeyStore: InMemoryDeviceKeyStore
        let clock: ManualUnlockClock
        let work: SpyUnlockWork
        let attemptStorage: LoggingAttemptStorage
        let attemptClock: FakeAppLockClock
        /// What the attempt counter and the unlock work did, in order.
        let log: SharedMutex<[String]>
        let realItem: VaultItem
        let realState: VaultRecordState
        let duressState: VaultRecordState

        let directory = EncryptedVaultFixture.inMemoryDirectory

        var fileURL: URL {
            directory.appending(path: EncryptedVaultFile.fileName)
        }

        var stateFile: VaultStorageStateFile {
            VaultStorageStateFile(directory: directory, fileSystem: base)
        }

        func bytes() throws -> Data {
            try #require(try base.contents(of: fileURL))
        }

        func contents() throws -> VaultSlotFile {
            try VaultSlotFile(bytes: bytes())
        }

        func passwordKey(_ password: String) throws -> VaultSlotRootKey {
            try contents().header.passwordKey(for: password)
        }

        /// Every slot the password opens, in the file on disk.
        func slots(openedBy password: String, in file: VaultSlotFile? = nil) throws -> [Int] {
            let file = try file ?? contents()
            return try slots(openedBy: file.header.passwordKey(for: password), in: file)
        }

        func slots(openedBy key: VaultSlotRootKey, in file: VaultSlotFile? = nil) throws -> [Int] {
            let file = try file ?? contents()
            return VaultSlotFile.slotIndices.filter { (try? file.openSlot($0, with: key)) != nil }
        }

        func savedState(inSlot index: Int, with key: VaultSlotRootKey) throws -> VaultRecordState {
            let file = try contents()
            return try EncryptedVaultPayload.decode(slot: file.openSlot(index, with: key), in: file)
        }

        func temporaryFileNames() throws -> [String] {
            try base.contentsOfDirectory(at: directory)
                .map(\.lastPathComponent)
                .filter { $0.hasPrefix(EncryptedVaultFile.temporaryFilePrefix) }
        }

        /// Launches again: recovers from any change underway, as the app does, with no faults.
        func relaunch() throws -> VaultStorageState.Mode {
            fileSystem.inject(nil)
            return try VaultStorageRecovery(directory: directory, fileSystem: base, deviceKeyStore: deviceKeyStore)
                .recoverAtLaunch()
        }
    }

    /// A file with a real vault in slot 4 and a duress vault in slot 11, and a session with one of them open.
    ///
    /// - Parameters:
    ///   - mode: `password`, or `deviceKey`, when the real vault is wrapped with a device key instead.
    ///   - password: The real vault's password.
    ///   - openedWith: The password that opened the session's vault, in the `password` mode.
    ///   - deviceKey: A device key in the keychain, in the `password` mode. It opens nothing.
    private static func makeSUT(
        mode: VaultStorageState.Mode = .password,
        password: String = "real",
        openedWith: String? = nil,
        deviceKey: SymmetricKey? = nil,
        wrapStamper: any VaultWrapStamping = VaultWallClockWrapStamper(),
        backgroundTime: (FaultInjectingSlotFileSystem) -> VaultBackgroundTime = { _ in .none },
    ) async throws -> SUT {
        let base = InMemorySlotFileSystem()
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: base)
        let directory = EncryptedVaultFixture.inMemoryDirectory
        let deviceKeyStore = InMemoryDeviceKeyStore(key: mode == .deviceKey ? SymmetricKey(size: .bits256) : deviceKey)
        let realItem = uniqueVaultItem()
        let realState = try EncryptedVaultStoreTests.state(items: [realItem])
        let duressState = try EncryptedVaultStoreTests.state(items: [uniqueVaultItem()])

        var contents = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
        let realKey: VaultSlotRootKey = if mode == .deviceKey, let key = deviceKeyStore.key {
            .device(key)
        } else {
            try contents.header.passwordKey(for: password)
        }
        try contents.createVault(
            inSlot: realSlot,
            rootKey: realKey,
            payload: EncryptedVaultPayload.encode(realState),
            wrappedAt: Self.longAgo,
        )
        try contents.createVault(
            inSlot: duressSlot,
            rootKey: contents.header.passwordKey(for: "duress"),
            payload: EncryptedVaultPayload.encode(duressState),
            wrappedAt: Self.longAgo,
        )
        let file = EncryptedVaultFile(
            directory: directory,
            fileSystem: fileSystem,
            protection: EncryptedVaultFile.protection(for: mode),
        )
        try base.createFile(at: file.url, contents: contents.bytes, protection: file.protection)
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        try stateFile.write(VaultStorageState(mode: mode, unlockDeadline: deadline))

        let session = VaultStoreSession(target: .locked)
        let clock = ManualUnlockClock()
        let log = SharedMutex([String]())
        let attemptStorage = LoggingAttemptStorage(log: log)
        let attemptClock = FakeAppLockClock()
        let attemptCounter = AppLockPasswordAttemptCounter(storage: attemptStorage, clock: attemptClock)
        let work = SpyUnlockWork(log: log, clock: clock)
        let unlockService = VaultUnlockService(
            file: EncryptedVaultFile(directory: directory, fileSystem: fileSystem),
            session: session,
            attemptCounter: attemptCounter,
            deadlineStore: stateFile,
            deviceKeyStore: deviceKeyStore,
            purgeVaultContents: {},
            clock: clock,
            work: work,
            availableMemory: { nil },
        )
        let service = VaultPasswordChangeService(
            directory: directory,
            fileSystem: fileSystem,
            session: session,
            unlockService: unlockService,
            attemptCounter: attemptCounter,
            deviceKeyStore: deviceKeyStore,
            wrapStamper: wrapStamper,
            backgroundTime: backgroundTime(fileSystem),
        )
        if mode == .deviceKey {
            try await unlockService.unlockWithDeviceKey()
        } else {
            #expect(try await unlockService.unlock(password: openedWith ?? password) == .unlocked)
        }

        return SUT(
            service: service,
            unlockService: unlockService,
            session: session,
            fileSystem: fileSystem,
            base: base,
            deviceKeyStore: deviceKeyStore,
            clock: clock,
            work: work,
            attemptStorage: attemptStorage,
            attemptClock: attemptClock,
            log: log,
            realItem: realItem,
            realState: realState,
            duressState: duressState,
        )
    }

    private func makeSUT(
        mode: VaultStorageState.Mode = .password,
        password: String = "real",
        openedWith: String? = nil,
        deviceKey: SymmetricKey? = nil,
        wrapStamper: any VaultWrapStamping = VaultWallClockWrapStamper(),
        backgroundTime: (FaultInjectingSlotFileSystem) -> VaultBackgroundTime = { _ in .none },
    ) async throws -> SUT {
        try await Self.makeSUT(
            mode: mode,
            password: password,
            openedWith: openedWith,
            deviceKey: deviceKey,
            wrapStamper: wrapStamper,
            backgroundTime: backgroundTime,
        )
    }

    /// Only slot `index` differs between the two copies of the file: the header, and every other slot, are the
    /// same byte for byte.
    private static func expectOnlySlotChanged(
        _ index: Int,
        from before: VaultSlotFile,
        to after: VaultSlotFile,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        #expect(after.bytes.count == before.bytes.count, sourceLocation: sourceLocation)
        #expect(
            after.bytes.prefix(VaultSlotFile.Header.length) == before.bytes.prefix(VaultSlotFile.Header.length),
            sourceLocation: sourceLocation,
        )
        for other in VaultSlotFile.slotIndices where other != index {
            #expect(
                after.bytes[after.slotRange(other)] == before.bytes[before.slotRange(other)],
                "slot \(other)",
                sourceLocation: sourceLocation,
            )
        }
    }

    private static func keyBox(of index: Int, in file: VaultSlotFile) -> Range<Int> {
        let start = file.slotRange(index).lowerBound + VaultSlotFile.slotNonceLength
        return start ..< start + VaultSlotFile.keyBoxLength
    }

    private static func body(of index: Int, in file: VaultSlotFile) -> Range<Int> {
        file.slotRange(index).lowerBound + VaultSlotFile.bodyOffset ..< file.slotRange(index).upperBound
    }

    private static func bytes(of key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}
