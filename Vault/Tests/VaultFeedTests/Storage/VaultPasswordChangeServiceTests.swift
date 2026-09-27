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
    private static let lastAttempt = AppLockPasswordAttemptCounter.eraseThreshold - 1
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
        #expect(try await sut.unlockService.unlock(password: "real") == .wrongPassword(reachesEraseThreshold: false))
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

        #expect(result == .wrongPassword(reachesEraseThreshold: false))
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

        #expect(result == .wrongPassword(reachesEraseThreshold: false))
        #expect(try sut.bytes() == before)
        #expect(!sut.log.value.contains("reset the count"))
    }

    /// A wrong current password counts towards the erase after too many, as a wrong unlock does, but Settings never
    /// tries the one that would reach it: that's only tried at the lock screen (VAULT-34).
    @Test
    func changePassword_withWrongPasswordsUpToTheEraseThreshold_stopsBeforeIt() async throws {
        let sut = try await makeSUT()
        sut.attemptStorage.setRecord(count: Self.lastAttempt - 1, latestAt: sut.attemptClock.now)
        sut.attemptClock.advance(by: .seconds(30 * 86400))

        let ninth = try await sut.service.changePassword(current: "wrong", new: "new")
        sut.attemptClock.advance(by: .seconds(30 * 86400))
        let tenth = try await sut.service.changePassword(current: "wrong", new: "new")

        #expect(ninth == .wrongPassword(reachesEraseThreshold: false))
        #expect(tenth == .onlyAtTheLockScreen)
        #expect(try sut.attemptStorage.load()?.count == Self.lastAttempt)
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

        #expect(result == .wrongPassword(reachesEraseThreshold: false))
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

// MARK: - Erasing after failed passwords

extension VaultPasswordChangeServiceTests {
    /// A setting of the device, in its shared defaults: nothing in the vault's file changes.
    @Test(arguments: [true, false])
    func setErasesAfterFailedPasswords_withTheCurrentPassword_setsItAndChangesNoFile(erases: Bool) async throws {
        let sut = try await makeSUT()
        sut.settings.erasesAfterFailedPasswords = !erases
        let before = try sut.bytes()
        sut.log.modify { $0.removeAll() }

        let result = try await sut.service.setErasesAfterFailedPasswords(erases, current: "real")

        #expect(result == .changed)
        #expect(sut.settings.erasesAfterFailedPasswords == erases)
        #expect(try sut.bytes() == before)
        // An attempt like any other: counted, then reset once it's right.
        #expect(sut.log.value.first == "count the attempt")
        #expect(sut.log.value.last == "reset the count")
    }

    /// Any vault's own password turns it on or off for every vault, a duress vault's included. That's accepted: see
    /// "Consequences to accept" in `docs/on-device-encryption.md`.
    @Test(arguments: [true, false])
    func setErasesAfterFailedPasswords_fromADuressVault_setsItForTheDevice(erases: Bool) async throws {
        let sut = try await makeSUT(openedWith: "duress")
        sut.settings.erasesAfterFailedPasswords = !erases

        let result = try await sut.service.setErasesAfterFailedPasswords(erases, current: "duress")

        #expect(result == .changed)
        #expect(sut.settings.erasesAfterFailedPasswords == erases)
    }

    /// Another vault's password is as wrong as any other, as for changing the password.
    @Test(arguments: ["wrong", "duress"])
    func setErasesAfterFailedPasswords_withAPasswordThatIsNotTheOpenVaults_isWrongAndChangesNothing(
        password: String,
    ) async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()

        let result = try await sut.service.setErasesAfterFailedPasswords(true, current: password)

        #expect(result == .wrongPassword(reachesEraseThreshold: false))
        #expect(!sut.settings.erasesAfterFailedPasswords)
        #expect(try sut.bytes() == before)
    }

    /// Settings never tries the attempt that would make the tenth in a row, erasing on or off, and whatever's
    /// entered: it's only tried at the lock screen. Nothing's counted or changed.
    @Test(arguments: [Self.lastAttempt, Self.lastAttempt + 1, Self.lastAttempt + 4], ["real", "wrong"])
    func setErasesAfterFailedPasswords_atTheLastAttempt_isOnlyAtTheLockScreen(
        counted: Int,
        password: String,
    ) async throws {
        let sut = try await makeSUT()
        sut.attemptStorage.setRecord(count: counted, latestAt: sut.attemptClock.now)
        sut.attemptClock.advance(by: .seconds(60 * 60))
        sut.log.modify { $0.removeAll() }
        let before = try sut.bytes()

        let result = try await sut.service.setErasesAfterFailedPasswords(true, current: password)

        #expect(result == .onlyAtTheLockScreen)
        #expect(!sut.settings.erasesAfterFailedPasswords)
        #expect(try sut.bytes() == before)
        #expect(sut.log.value.isEmpty)
        #expect(await !sut.session.isLocked)
    }

    /// Changing the password and turning it off stop there too.
    @Test
    func changeAndTurnOff_atTheLastAttempt_areOnlyAtTheLockScreen() async throws {
        let sut = try await makeSUT()
        sut.attemptStorage.setRecord(count: Self.lastAttempt, latestAt: sut.attemptClock.now)
        sut.attemptClock.advance(by: .seconds(60 * 60))

        #expect(try await sut.service.changePassword(current: "real", new: "new") == .onlyAtTheLockScreen)
        #expect(try await sut.service.turnOffPassword(current: "real") == .onlyAtTheLockScreen)
        #expect(try sut.stateOnDisk().mode == .password)
    }

    @Test
    func setErasesAfterFailedPasswords_whileTheUserMustWait_triesNothing() async throws {
        let sut = try await makeSUT()
        sut.attemptStorage.setRecord(count: 5, latestAt: sut.attemptClock.now)

        let result = try await sut.service.setErasesAfterFailedPasswords(true, current: "real")

        #expect(result == .mustWait(.seconds(60)))
        #expect(!sut.settings.erasesAfterFailedPasswords)
    }

    @Test
    func setErasesAfterFailedPasswords_withThePasswordOff_throws() async throws {
        let sut = try await makeSUT(mode: .deviceKey)

        await #expect(throws: VaultPasswordChangeError.passwordIsNotOn) {
            try await sut.service.setErasesAfterFailedPasswords(true, current: "real")
        }
        #expect(!sut.settings.erasesAfterFailedPasswords)
    }

    /// Erasing after failed passwords means nothing without one, whichever vault turned it off.
    @Test(arguments: ["real", "duress"])
    func turnOffPassword_turnsErasingOff(vault: String) async throws {
        let sut = try await makeSUT(openedWith: vault)
        sut.settings.erasesAfterFailedPasswords = true

        _ = try await sut.service.turnOffPassword(current: vault)

        #expect(!sut.settings.erasesAfterFailedPasswords)
    }

    @Test
    func turnOffPassword_wrong_leavesErasingOn() async throws {
        let sut = try await makeSUT()
        sut.settings.erasesAfterFailedPasswords = true

        _ = try await sut.service.turnOffPassword(current: "wrong")

        #expect(sut.settings.erasesAfterFailedPasswords)
    }

    /// A password turned back on starts with erasing off, as a new one does.
    @Test
    func turnOnPassword_startsWithErasingOff() async throws {
        let sut = try await makeSUT(mode: .deviceKey)
        sut.settings.erasesAfterFailedPasswords = true

        try await sut.service.turnOnPassword("new")

        #expect(!sut.settings.erasesAfterFailedPasswords)
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

    /// With the password off, no password opens the vault, so trying one is refused before it's counted: a wrong
    /// attempt counts towards an erase.
    @Test
    func unlock_withThePasswordOff_isRefusedWithoutCounting() async throws {
        let sut = try await makeSUT()
        _ = try await sut.service.turnOffPassword(current: "real")
        await sut.unlockService.lock()
        sut.log.modify { $0.removeAll() }

        await #expect(throws: VaultUnlockError.passwordIsOff) {
            try await sut.unlockService.unlock(password: "real")
        }

        #expect(sut.log.value.isEmpty)
        #expect(try sut.attemptStorage.load() == nil)
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

    /// The app stops at any step, keychain steps included. At the next launch, the vault is intact and wrapped with the
    /// key the mode says:
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
        if operation == .turnOff {
            #expect(sut.deviceKeyStore.key == nil)
        } else {
            #expect(try sut.slots(openedBy: .device(#require(sut.deviceKeyStore.key))) == [Self.realSlot])
        }
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
        // Only the system surfaces can be left to catch up with the mode it landed in, for the app to finish.
        let surfacesStep: VaultStorageState.Transition = mode == .deviceKey
            ? .syncingSystemSurfaces
            : .clearingSystemSurfaces
        #expect(try [nil, surfacesStep].contains(sut.stateFile.read().transition), comment)
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
        // With the password on, launch recovery deletes a device key it's shown opens nothing, however the change
        // ended, and with it off, the key is there.
        #expect((sut.deviceKeyStore.key != nil) == (mode == .deviceKey), comment)
    }
}

// MARK: - A mode that can't be saved

extension VaultPasswordChangeServiceTests {
    /// The rekey worked, but the state can't be saved, however often it's tried. The change is made, and the
    /// journal stays. Unlocking with a password is refused without counting until it's settled, so a right password
    /// isn't counted as wrong while the device key wraps the vault. The device key still opens it.
    @Test
    func turnOffPassword_whoseModeCantBeSaved_refusesPasswordsWithoutCountingUntilSettled() async throws {
        let rename = try await Self.stepNumber(of: "rename temp to vault-slots.v1", in: .turnOff)
        let sut = try await makeSUT()
        sut.fileSystem.inject(.failEvery(stepNamed: "create state temp", fromStep: rename))

        #expect(try await sut.service.turnOffPassword(current: "real") == .changed)

        #expect(try sut.stateOnDisk() == VaultStorageState(
            mode: .password,
            transition: .turningOff,
            unlockDeadline: Self.deadline,
        ))
        await sut.unlockService.lock()
        sut.log.modify { $0.removeAll() }
        await #expect(throws: VaultUnlockError.passwordChangeUnsettled) {
            try await sut.unlockService.unlock(password: "real")
        }
        #expect(sut.log.value.isEmpty)
        try await sut.unlockService.unlockWithDeviceKey()
        #expect(try await sut.session.retrieve(query: .init()).items == [sut.realItem])

        sut.fileSystem.inject(nil)
        #expect(try await sut.service.settleInterruptedChange() == .deviceKey)
        #expect(try sut.stateOnDisk() == VaultStorageState(mode: .deviceKey, unlockDeadline: Self.deadline))
    }

    /// Turning the password on can't save its mode either. The device key opens nothing now, so the new password
    /// still unlocks, without waiting for the mode to be settled. Settling it later deletes the device key.
    @Test
    func turnOnPassword_whoseModeCantBeSaved_stillUnlocksWithTheNewPassword() async throws {
        let rename = try await Self.stepNumber(of: "rename temp to vault-slots.v1", in: .turnOn)
        let sut = try await makeSUT(mode: .deviceKey)
        sut.fileSystem.inject(.failEvery(stepNamed: "create state temp", fromStep: rename))

        try await sut.service.turnOnPassword("new")

        #expect(try sut.stateOnDisk().transition == .turningOn)
        await sut.unlockService.lock()
        #expect(try await sut.unlockService.unlock(password: "new") == .unlocked)
        #expect(try await sut.session.retrieve(query: .init()).items == [sut.realItem])

        sut.fileSystem.inject(nil)
        #expect(try await sut.service.settleInterruptedChange() == .password)
        #expect(try sut.stateOnDisk() == VaultStorageState(mode: .password, unlockDeadline: Self.deadline))
        #expect(sut.deviceKeyStore.key == nil)
    }

    /// The next change settles one that couldn't save its mode before it starts, so the vault isn't stuck until the
    /// app relaunches.
    @Test
    func changePassword_afterATurnOnWhoseModeCantBeSaved_settlesItFirst() async throws {
        let rename = try await Self.stepNumber(of: "rename temp to vault-slots.v1", in: .turnOn)
        let sut = try await makeSUT(mode: .deviceKey)
        sut.fileSystem.inject(.failEvery(stepNamed: "create state temp", fromStep: rename))
        try await sut.service.turnOnPassword("new")
        sut.fileSystem.inject(nil)

        let result = try await sut.service.changePassword(current: "new", new: "newer")

        #expect(result == .changed)
        #expect(try sut.stateOnDisk() == VaultStorageState(mode: .password, unlockDeadline: Self.deadline))
        #expect(try sut.slots(openedBy: "newer") == [Self.realSlot])
    }

    /// A rekey that fails leaves the file as it was, and the mode is settled from that straight away: nothing is
    /// left for a relaunch, and a device key made for it goes.
    @Test
    func turnOffPassword_whoseRekeyFails_settlesBackToThePasswordAtOnce() async throws {
        let createTemp = try await Self.stepNumber(of: "create temp", in: .turnOff)
        let sut = try await makeSUT()
        sut.fileSystem.inject(.fail(atStep: createTemp))

        await #expect(throws: FaultInjectingSlotFileSystem.InjectedFault.self) {
            try await sut.service.turnOffPassword(current: "real")
        }

        #expect(try sut.stateOnDisk() == VaultStorageState(mode: .password, unlockDeadline: Self.deadline))
        #expect(sut.deviceKeyStore.key == nil)
        await sut.unlockService.lock()
        #expect(try await sut.unlockService.unlock(password: "real") == .unlocked)
    }
}

// MARK: - Locking

extension VaultPasswordChangeServiceTests {
    /// Locking while the vault is rekeyed waits for the rekey to finish, as it does for a save.
    @Test
    func lock_whileRekeying_waitsForTheRekeyToFinish() async throws {
        let sut = try await makeSUT()
        sut.gate.holdNextWrite()
        let change = Task { try await sut.service.changePassword(current: "real", new: "new") }
        await sut.gate.waitUntilHolding()

        let lockFinished = SharedMutex(false)
        let locking = Task {
            await sut.unlockService.lock()
            lockFinished.modify { $0 = true }
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!lockFinished.value)

        sut.gate.release()
        #expect(try await change.value == .changed)
        await locking.value
        #expect(lockFinished.value)
        #expect(await sut.session.isLocked)
        #expect(try sut.slots(openedBy: "new") == [Self.realSlot])
    }

    /// The vault locks after the current password was checked and before the rekey: nothing is changed, not even a
    /// device key made.
    @Test(arguments: [Operation.change, .turnOff])
    func operation_lockedAfterTheCheck_changesNothing(operation: Operation) async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()
        let stateBefore = try sut.stateOnDisk()
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
            try await operation.run(on: sut)
        }

        #expect(try sut.bytes() == before)
        #expect(try sut.stateOnDisk() == stateBefore)
        #expect(sut.deviceKeyStore.key == nil)
    }
}

// MARK: - Wrap times

extension VaultPasswordChangeServiceTests {
    /// Every rekey is stamped by the device's wrap stamper (`VaultDeviceWrapStamper`): after the stamp, which
    /// unlocking moved on to now, and after the slot's own wrap.
    @Test(arguments: Operation.allCases)
    func operation_stampsTheWrapAfterTheDevicesLastUse(operation: Operation) async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let sut = try await makeSUT(mode: operation.startMode, now: { now })

        try await operation.run(on: sut)

        let key: VaultSlotRootKey = if operation == .turnOff {
            try .device(#require(sut.deviceKeyStore.key))
        } else {
            try sut.passwordKey("new")
        }
        let wrappedAt = try sut.contents().openSlot(Self.realSlot, with: key).wrappedAt
        #expect(UInt64((wrappedAt.timeIntervalSince1970 * 1000).rounded()) == 1_750_000_000_001)
        #expect(sut.wrapStampStorage.value == 1_750_000_000_001)
    }

    /// A clock set back doesn't make the rekeyed vault older than the duress vault, so changing the real vault's
    /// password to the duress vault's, then unlocking with it, still opens the vault it was just set for. Otherwise
    /// it would show which vault a password opens, without counting an attempt.
    @Test
    func changePassword_withTheClockSetBack_stillWrapsAfterEveryOtherVault() async throws {
        let yearBefore = Self.longAgo.addingTimeInterval(-365 * 86400)
        let sut = try await makeSUT(now: { yearBefore })

        _ = try await sut.service.changePassword(current: "real", new: "duress")

        await sut.unlockService.lock()
        #expect(try await sut.unlockService.unlock(password: "duress") == .unlocked)
        #expect(try await sut.session.retrieve(query: .init()).items == [sut.realItem])
    }

    /// A wrap whose stamp can't be saved could get the same time as a later one, so nothing is wrapped.
    @Test
    func changePassword_thatCantSaveTheWrapStamp_changesNothing() async throws {
        let sut = try await makeSUT()
        let before = try sut.bytes()
        sut.wrapStampStorage.failToSave()

        await #expect(throws: InMemoryWrapStampStorage.Failure.self) {
            try await sut.service.changePassword(current: "real", new: "new")
        }

        #expect(try sut.bytes() == before)
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

// MARK: - System surfaces

extension VaultPasswordChangeServiceTests {
    /// Turning the password off brings QuickType and the widgets back: they're filled again from the vault, and the
    /// journal's done with.
    @Test
    func turnOffPassword_fillsQuickTypeAgainAndReloadsTheWidgets() async throws {
        let sut = try await makeSUT()

        #expect(try await sut.service.turnOffPassword(current: "real") == .changed)

        #expect(sut.surfaces.value == ["fill QuickType and reload widgets"])
        #expect(try sut.stateFile.read() == VaultStorageState(mode: .deviceKey, unlockDeadline: Self.deadline))
    }

    @Test
    func turnOnPassword_emptiesQuickTypeAndReloadsTheWidgets() async throws {
        let sut = try await makeSUT(mode: .deviceKey)

        try await sut.service.turnOnPassword("new password")

        #expect(sut.surfaces.value == ["empty QuickType and reload widgets"])
        #expect(try sut.stateFile.read() == VaultStorageState(mode: .password, unlockDeadline: Self.deadline))
    }

    /// If the app stops after the password is off, before QuickType is filled again, the journal says so, and the
    /// next launch fills it.
    @Test
    func turnOffPassword_stoppedBeforeFillingQuickType_theNextLaunchFillsIt() async throws {
        let sut = try await makeSUT()
        sut.surfaceHooksFail.modify { $0 = true }

        #expect(try await sut.service.turnOffPassword(current: "real") == .changed)
        #expect(try sut.stateFile.read().transition == .syncingSystemSurfaces)
        #expect(try VaultAccessMode(state: sut.stateFile.read()) == .deviceKey)

        let recovery = VaultStorageRecovery(
            directory: sut.directory,
            fileSystem: sut.fileSystem,
            deviceKeyStore: sut.deviceKeyStore,
        )
        #expect(try recovery.recoverAtLaunch() == .deviceKey)
        try await recovery.finishSyncingSystemSurfaces {
            sut.surfaces.modify { $0.append("fill QuickType at launch") }
        }

        #expect(sut.surfaces.value == ["fill QuickType at launch"])
        #expect(try sut.stateFile.read().transition == nil)
    }

    /// Likewise turning it back on: QuickType mustn't keep anything once only the password opens the vault.
    @Test
    func turnOnPassword_stoppedBeforeEmptyingQuickType_theNextLaunchEmptiesIt() async throws {
        let sut = try await makeSUT(mode: .deviceKey)
        sut.surfaceHooksFail.modify { $0 = true }

        try await sut.service.turnOnPassword("new password")
        #expect(try sut.stateFile.read().transition == .clearingSystemSurfaces)
        #expect(try VaultAccessMode(state: sut.stateFile.read()) == .password)

        let recovery = VaultStorageRecovery(
            directory: sut.directory,
            fileSystem: sut.fileSystem,
            deviceKeyStore: sut.deviceKeyStore,
        )
        #expect(try recovery.recoverAtLaunch() == .password)
        try await recovery.finishClearingSystemSurfaces {
            sut.surfaces.modify { $0.append("empty QuickType at launch") }
        }

        #expect(sut.surfaces.value == ["empty QuickType at launch"])
        #expect(try sut.stateFile.read().transition == nil)
    }

    /// With QuickType still to fill, the password can still be turned back on: that empties it instead.
    @Test
    func turnOnPassword_whileQuickTypeIsStillToFill_emptiesItInstead() async throws {
        let sut = try await makeSUT()
        sut.surfaceHooksFail.modify { $0 = true }
        #expect(try await sut.service.turnOffPassword(current: "real") == .changed)
        sut.surfaceHooksFail.modify { $0 = false }

        try await sut.service.turnOnPassword("new password")

        #expect(sut.surfaces.value == ["empty QuickType and reload widgets"])
        #expect(try sut.stateFile.read() == VaultStorageState(mode: .password, unlockDeadline: Self.deadline))
    }
}

extension VaultPasswordChangeServiceTests {
    struct SUT {
        let service: VaultPasswordChangeService
        let unlockService: VaultUnlockService
        let session: VaultStoreSession
        /// Everything the services do to files goes through this.
        let fileSystem: FaultInjectingSlotFileSystem
        /// The files themselves, for the test to look at without taking a step.
        let base: InMemorySlotFileSystem
        /// Can hold the next file written, between `base` and `fileSystem`.
        let gate: GatedSlotFileSystem
        /// The keychain's device key, for the test to look at without taking a step. The services reach it through
        /// `fileSystem`'s steps.
        let deviceKeyStore: InMemoryDeviceKeyStore
        let wrapStampStorage: InMemoryWrapStampStorage
        let clock: ManualUnlockClock
        let work: SpyUnlockWork
        let attemptStorage: LoggingAttemptStorage
        let attemptClock: FakeAppLockClock
        /// What the attempt counter and the unlock work did, in order.
        let log: SharedMutex<[String]>
        /// The app lock's settings, with erasing after failed passwords.
        let settings: AppLockSettingsStore
        let realItem: VaultItem
        let realState: VaultRecordState
        let duressState: VaultRecordState
        /// What the surface hooks did, in order.
        let surfaces: SharedMutex<[String]>
        /// Makes the surface hooks fail, as if the app stopped before they ran.
        let surfaceHooksFail: SharedMutex<Bool>

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

        func stateOnDisk() throws -> VaultStorageState {
            try stateFile.read()
        }

        /// Launches again: recovers from any change underway, as the app does, with no faults.
        func relaunch() throws -> VaultStorageRecovery.Outcome {
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
    ///   - now: The device's clock, for wrap stamps.
    private static func makeSUT(
        mode: VaultStorageState.Mode = .password,
        password: String = "real",
        openedWith: String? = nil,
        deviceKey: SymmetricKey? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        backgroundTime: (FaultInjectingSlotFileSystem) -> VaultBackgroundTime = { _ in .none },
    ) async throws -> SUT {
        let base = InMemorySlotFileSystem()
        let gate = GatedSlotFileSystem(wrapping: base)
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: gate)
        let directory = EncryptedVaultFixture.inMemoryDirectory
        let deviceKeyStore = InMemoryDeviceKeyStore(key: mode == .deviceKey ? SymmetricKey(size: .bits256) : deviceKey)
        let keychain = FaultInjectingDeviceKeyStore(wrapping: deviceKeyStore, steps: fileSystem)
        let wrapStampStorage = InMemoryWrapStampStorage()
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
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        let unlockService = VaultUnlockService(
            file: EncryptedVaultFile(directory: directory, fileSystem: fileSystem),
            session: session,
            attemptCounter: attemptCounter,
            deadlineStore: stateFile,
            deviceKeyStore: keychain,
            purgeVaultContents: {},
            clock: clock,
            work: work,
            availableMemory: { nil },
            wrapStamper: .inMemory(storage: wrapStampStorage, currentDate: now),
        )
        let surfaces = SharedMutex([String]())
        let surfaceHooksFail = SharedMutex(false)
        struct SurfaceHookFailure: Error {}
        let service = VaultPasswordChangeService(
            directory: directory,
            fileSystem: fileSystem,
            session: session,
            unlockService: unlockService,
            attemptCounter: attemptCounter,
            deviceKeyStore: keychain,
            settings: settings,
            backgroundTime: backgroundTime(fileSystem),
            hooks: VaultPasswordChangeService.Hooks(
                passwordDidTurnOff: {
                    guard !surfaceHooksFail.value else { throw SurfaceHookFailure() }
                    surfaces.modify { $0.append("fill QuickType and reload widgets") }
                },
                passwordDidTurnOn: {
                    guard !surfaceHooksFail.value else { throw SurfaceHookFailure() }
                    surfaces.modify { $0.append("empty QuickType and reload widgets") }
                },
            ),
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
            gate: gate,
            deviceKeyStore: deviceKeyStore,
            wrapStampStorage: wrapStampStorage,
            clock: clock,
            work: work,
            attemptStorage: attemptStorage,
            attemptClock: attemptClock,
            log: log,
            settings: settings,
            realItem: realItem,
            realState: realState,
            duressState: duressState,
            surfaces: surfaces,
            surfaceHooksFail: surfaceHooksFail,
        )
    }

    private func makeSUT(
        mode: VaultStorageState.Mode = .password,
        password: String = "real",
        openedWith: String? = nil,
        deviceKey: SymmetricKey? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        backgroundTime: (FaultInjectingSlotFileSystem) -> VaultBackgroundTime = { _ in .none },
    ) async throws -> SUT {
        try await Self.makeSUT(
            mode: mode,
            password: password,
            openedWith: openedWith,
            deviceKey: deviceKey,
            now: now,
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
