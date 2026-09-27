import CryptoKit
import Foundation
#if os(iOS)
import os
#endif

/// Unlocks the encrypted vault with the app lock password, and locks it again.
///
/// **Unlocking** (`unlock(password:)`), from a locked session:
///
/// 1. Counts the attempt with `AppLockPasswordAttemptCounter`, before anything is derived. If the user has to wait
///    after their last wrong attempts, it says how long, and tries nothing.
/// 2. Starts the device's unlock deadline.
/// 3. Derives `K_pw` from the password with Argon2id, off this actor.
/// 4. Tries every slot's key box, with no early exit.
/// 5. Opens one body: the slot that opened, or the most recently wrapped if more than one did. If none did, it opens
///    a decoy instead, a random slot's body with a throwaway key, which fails.
/// 6. Drops `K_pw` and every wrap key but the opened slot's. They're `SymmetricKey`s, which are zeroed when released.
///    The opened slot's wrap key and data key stay with its store until the vault locks.
/// 7. Waits for the deadline. Then it resets the count, moves the wrap stamp on
///    (`VaultDeviceWrapStamper.noteUse(ofVaultWrappedAt:)`), and switches the store session to the vault, or reports
///    a wrong password.
///
/// So real, duress and wrong passwords do the same work, and finish at the same deadline.
///
/// **The deadline** is set when the vault is created, at 1.5 times the derivation calibration expected. If deriving
/// the key and trying the slots (steps 3 and 4) take more than two thirds of it, for example after a restore onto a
/// slower iPhone, the deadline is raised to 1.5 times that, for that attempt and every later one, up to
/// `maximumDeadline`. It's never lowered.
///
/// - The work is timed in the thread's CPU time, not on a clock, so time the app spends suspended, or the device
///   asleep, doesn't count. The work is one thread's computation, so its CPU time is how long it takes when it isn't
///   held up. When the device is busy, an attempt can overrun the deadline without raising it. That shows how busy
///   the device is, not what the password opened.
/// - Only an attempt whose work finished and that's still wanted raises it.
/// - Only work that's the same whatever the password counts. Opening and decoding a vault doesn't: the deadline is
///   saved and every later attempt waits for it, so counting a large vault's decode would make every attempt, a
///   duress one included, show how large the largest vault opened is. A decode too slow to fit the third of the
///   deadline left for it overruns that one attempt instead, which is proportional to what the vault shows once
///   it's open anyway.
///
/// **Locking** (`lock()`) waits for any change already underway to finish saving, switches the store session to
/// `locked`, and purges what the app read from the vault.
///
/// See "Unlocking and locking" in `docs/on-device-encryption.md`. Never log, print or measure anything about the
/// password or which vault opened.
public actor VaultUnlockService {
    /// The memory the AutoFill extension keeps free on top of the key derivation's and the file's.
    static let memoryMargin = 16 << 20
    /// An attempt whose work takes more than two thirds of the deadline raises it to this multiple of the work.
    static let deadlineMultiplier = 1.5
    /// The longest the deadline goes: raised no further, and a longer one read from storage is taken as this.
    ///
    /// The derivation's passes are capped at 32 (`AppLockKeyDerivation.passesRange`). Those take about 0.7 s on an
    /// M5 Max, and perhaps 3 s on an iPhone four times slower; 1.5 times that is about 4.5 s. A deadline beyond this
    /// hides nothing a real device needs hiding, and would make every unlock wait.
    static let maximumDeadline = Duration.seconds(5)

    private let file: EncryptedVaultFile
    private let session: VaultStoreSession
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let deadlineStore: any VaultUnlockDeadlineStoring
    private let deviceKeyStore: any VaultDeviceKeyStoring
    private let purgeVaultContents: @Sendable () async -> Void
    private let clock: any VaultUnlockClock
    private let work: any VaultUnlockWork
    private let availableMemory: @Sendable () -> Int?
    /// Stamps key wraps, and is raised to every vault that opens.
    private let wrapStamper: VaultDeviceWrapStamper
    /// Checked before every save of a vault this opens, in the AutoFill extension. `nil` in the app.
    private let writeMemoryCheck: VaultWriteMemoryCheck?
    /// How the vault can be opened now, which an app extension checks before it opens the vault, and on every call to
    /// it once it has (`VaultAccessGuard`). `nil` in the app.
    private let currentAccessMode: (@Sendable () -> VaultAccessMode)?
    /// Keeps the app running until an attempt has finished, so it isn't suspended with the attempt counted and the
    /// count not yet reset for a right password.
    private let backgroundTime: VaultBackgroundTime

    private var isUnlocking = false

    /// - Parameters:
    ///   - directory: The directory the encrypted vault file is in.
    ///   - session: The store session the app reads and writes the vault through.
    ///   - attemptCounter: Counts every attempt before it's tried, and is reset when one opens a vault.
    ///   - purgeVaultContents: Forgets everything the app read from the vault. Called every time it locks.
    ///   - backgroundTime: Keeps the app running until an attempt has finished: `.application` in the app.
    public init(
        directory: URL,
        session: VaultStoreSession,
        attemptCounter: AppLockPasswordAttemptCounter,
        deadlineStore: any VaultUnlockDeadlineStoring,
        deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore(),
        purgeVaultContents: @escaping @Sendable () async -> Void,
        backgroundTime: VaultBackgroundTime = .none,
    ) {
        self.init(
            file: EncryptedVaultFile(directory: directory),
            session: session,
            attemptCounter: attemptCounter,
            deadlineStore: deadlineStore,
            deviceKeyStore: deviceKeyStore,
            purgeVaultContents: purgeVaultContents,
            wrapStamper: VaultDeviceWrapStamper(),
            backgroundTime: backgroundTime,
        )
    }

    /// - Parameters:
    ///   - availableMemory: The memory the process can still use, or `nil` if it has no limit.
    ///   - writeMemoryCheck: Checked before every save of a vault this opens, in the AutoFill extension.
    ///   - currentAccessMode: How the vault can be opened now, in an app extension, which checks it before it opens
    ///     the vault and on every call once it has.
    init(
        file: EncryptedVaultFile,
        session: VaultStoreSession,
        attemptCounter: AppLockPasswordAttemptCounter,
        deadlineStore: any VaultUnlockDeadlineStoring,
        deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore(),
        purgeVaultContents: @escaping @Sendable () async -> Void,
        clock: any VaultUnlockClock = ContinuousClock(),
        work: any VaultUnlockWork = LiveVaultUnlockWork(),
        availableMemory: @escaping @Sendable () -> Int? = VaultUnlockService.processAvailableMemory,
        wrapStamper: VaultDeviceWrapStamper,
        writeMemoryCheck: VaultWriteMemoryCheck? = nil,
        currentAccessMode: (@Sendable () -> VaultAccessMode)? = nil,
        backgroundTime: VaultBackgroundTime = .none,
    ) {
        self.file = file
        self.session = session
        self.attemptCounter = attemptCounter
        self.deadlineStore = deadlineStore
        self.deviceKeyStore = deviceKeyStore
        self.purgeVaultContents = purgeVaultContents
        self.clock = clock
        self.work = work
        self.availableMemory = availableMemory
        self.wrapStamper = wrapStamper
        self.writeMemoryCheck = writeMemoryCheck
        self.currentAccessMode = currentAccessMode
        self.backgroundTime = backgroundTime
    }

    /// What a vault this opens checks on every call, in an app extension.
    private func accessGuard(openedIn mode: VaultAccessMode, allowsWrites: Bool = true) -> VaultAccessGuard? {
        guard let currentAccessMode else { return nil }
        return VaultAccessGuard(openedIn: mode, currentMode: currentAccessMode, allowsWrites: allowsWrites)
    }

    /// Moves the wrap stamp on to a vault that's opened, as every unlock does, holding the file's lock with the wraps
    /// that stamp it. Best effort: a vault that opened stays open. In an app extension, only while the vault is still
    /// stored as it was, so an erase that's started, which deletes the stamp, isn't followed by a new one.
    private func noteUse(of file: EncryptedVaultFile, wrappedAt: Date, openedIn mode: VaultAccessMode) async {
        let accessGuard = accessGuard(openedIn: mode)
        try? await file.withLock { [wrapStamper] _ in
            guard accessGuard?.isStillOpen ?? true else { return }
            try wrapStamper.noteUse(ofVaultWrappedAt: wrappedAt)
        }
    }
}

/// How an attempt to unlock with the app lock password turned out.
public enum VaultUnlockResult: Equatable, Sendable {
    /// A vault opened, and the store session now reads and writes it.
    case unlocked
    /// No vault opened with the password.
    ///
    /// - reachesEraseThreshold: Whether this was `AppLockPasswordAttemptCounter.eraseThreshold` or more wrong
    ///   attempts in a row. If the user has turned on erasing after too many (VAULT-34), that's when to erase with
    ///   `VaultEraser.erase()`. Never show it: the lock screen shows only how long to wait.
    case wrongPassword(reachesEraseThreshold: Bool)
    /// The user has to wait this long after their last wrong attempts before trying again. Nothing was tried.
    case mustWait(Duration)
}

/// Whether a password is the open vault's (`VaultUnlockService.checkPassword(_:opensSlot:)`).
enum VaultPasswordCheck: Equatable, Sendable {
    case right
    /// As `VaultUnlockResult.wrongPassword(reachesEraseThreshold:)`: a wrong check counts towards an erase too.
    case wrong(reachesEraseThreshold: Bool)
    /// The user has to wait this long after their last wrong attempts. Nothing was tried.
    case mustWait(Duration)
    /// The check would have been the erase threshold's attempt in a row, which only the lock screen tries. Nothing
    /// was tried or counted.
    case stoppedBeforeEraseThreshold
}

public enum VaultUnlockError: Error, Equatable, Sendable {
    /// There's no encrypted vault file to unlock.
    case noEncryptedVault
    /// Another attempt is still underway.
    case attemptUnderway
    /// The store session isn't locked: a vault is open already.
    case notLocked
    /// An erase is underway (`VaultEraser`), so no vault may open, even with the right password. Finish the erase
    /// instead.
    case erasing
    /// There's no device key, so the password can't be off.
    case noDeviceKey
    /// No slot opens with the device key.
    case deviceKeyOpensNoVault
    /// The password is off, so device authentication opens the vault (`unlockWithDeviceKey()`), and no password
    /// does. Nothing was tried or counted.
    case passwordIsOff
    /// The vault isn't stored with the device key now: the password is on, a change is underway, or it's being
    /// erased. Nothing was read. Only an app extension checks, before it opens the vault with the device key.
    case deviceKeyNotInUse
    /// The password was being turned off or back on, how that ended hasn't been recorded yet, and the device key
    /// still wraps the vault, so a right password could look wrong. Nothing was tried or counted. Settling it
    /// (`VaultPasswordChangeService.settleInterruptedChange()`, or the next launch) lets unlocking go ahead.
    case passwordChangeUnsettled
    /// The attempt would have made `AppLockPasswordAttemptCounter.eraseThreshold` or more wrong attempts in a row, and
    /// the caller asked to stop before that: the AutoFill extension, which leaves the attempt that could erase to the
    /// app (VAULT-34). Nothing was tried or counted.
    case stoppedBeforeEraseThreshold
}

// MARK: - Unlocking

extension VaultUnlockService {
    /// Tries the password, and if it opens a vault, switches the store session to it.
    ///
    /// Once the attempt is counted, it returns at the device's unlock deadline whatever happens, and throws only
    /// then: for example if the password opened a vault that can't be read.
    ///
    /// - Parameter stoppingBeforeEraseThreshold: Whether to refuse, without counting it, an attempt that would make
    ///   `AppLockPasswordAttemptCounter.eraseThreshold` or more wrong ones in a row
    ///   (`VaultUnlockError.stoppedBeforeEraseThreshold`). The AutoFill extension does.
    /// - Throws: `VaultUnlockError`, an error counting the attempt or reading the file, or `CancellationError` if the
    ///   vault locked, or the task was cancelled, while the attempt was underway. Its result is thrown away then, but
    ///   if the password opened a vault, the count is still reset first.
    public func unlock(
        password: String,
        stoppingBeforeEraseThreshold: Bool = false,
    ) async throws -> VaultUnlockResult {
        guard !isUnlocking else { throw VaultUnlockError.attemptUnderway }
        isUnlocking = true
        defer { isUnlocking = false }
        guard await session.isLocked else { throw VaultUnlockError.notLocked }
        return try await backgroundTime.whileRunning {
            try await unlockWhileRunning(password: password, stoppingBeforeEraseThreshold: stoppingBeforeEraseThreshold)
        }
    }

    private func unlockWhileRunning(
        password: String,
        stoppingBeforeEraseThreshold: Bool,
    ) async throws -> VaultUnlockResult {
        let lockEpoch = await session.lockEpoch

        let attempt: Attempt
        switch try await attemptPassword(
            password,
            opensBody: true,
            stoppingBeforeEraseThreshold: stoppingBeforeEraseThreshold,
            lockEpoch: lockEpoch,
            isRight: { attempt in
                if case .success(.some) = attempt.outcome {
                    true
                } else {
                    false
                }
            },
        ) {
        case let .mustWait(remaining): return .mustWait(remaining)
        case .stoppedBeforeEraseThreshold: throw VaultUnlockError.stoppedBeforeEraseThreshold
        case let .finished(finished): attempt = finished
        }
        switch attempt.outcome {
        case .success(nil):
            return .wrongPassword(reachesEraseThreshold: attempt.reachesEraseThreshold)
        case let .success(opened?):
            try await attemptCounter.reset()
            // Moves the stamp on to now, as every unlock does, so it shows when the device was last used rather than
            // when a key was last wrapped, and so a wrap made from now on follows this vault's even on a device that's
            // lost its stamp.
            await noteUse(of: file, wrappedAt: opened.slot.wrappedAt, openedIn: .password)
            let store = EncryptedVaultStore(
                file: file,
                slot: opened.slot,
                state: opened.state,
                work: work,
                wrapStamper: wrapStamper,
                memoryCheck: writeMemoryCheck,
                accessGuard: accessGuard(openedIn: .password),
            )
            // The session only switches if it hasn't locked since this attempt began, checked on the session itself,
            // so a lock can't slip in between the check and the switch.
            guard await session.switchTo(.unlocked(store), unlessLockedSince: lockEpoch) else {
                throw CancellationError()
            }
            return .unlocked
        case let .failure(error):
            throw error
        }
    }

    /// Checks the password against the open vault, to change it or turn it off (`VaultPasswordChangeService`).
    ///
    /// It's an attempt like unlocking, finishing at the same deadline: counted first, the same derivation and a trial
    /// of every slot, and the count reset if it's right. It opens no body. Right means it opens `index`, the open
    /// vault's slot: a password that opens another vault is as wrong as any other, so this never shows that another
    /// vault exists.
    ///
    /// It never tries an attempt that would make `AppLockPasswordAttemptCounter.eraseThreshold` or more wrong ones in
    /// a row, erasing on or off (`.stoppedBeforeEraseThreshold`). That one is only ever tried at the lock screen, where
    /// a wrong one erases there and then, if erasing is on (VAULT-34).
    ///
    /// - Throws: As `unlock(password:)` does, and `CancellationError` if the vault locked meanwhile.
    func checkPassword(_ password: String, opensSlot index: Int) async throws -> VaultPasswordCheck {
        guard !isUnlocking else { throw VaultUnlockError.attemptUnderway }
        isUnlocking = true
        defer { isUnlocking = false }
        return try await backgroundTime.whileRunning {
            try await checkPasswordWhileRunning(password, opensSlot: index)
        }
    }

    private func checkPasswordWhileRunning(
        _ password: String,
        opensSlot index: Int,
    ) async throws -> VaultPasswordCheck {
        let lockEpoch = await session.lockEpoch

        switch try await attemptPassword(
            password,
            opensBody: false,
            stoppingBeforeEraseThreshold: true,
            lockEpoch: lockEpoch,
            isRight: { attempt in
                if case .failure = attempt.outcome {
                    return false
                }
                return attempt.openedSlots.contains(index)
            },
        ) {
        case let .mustWait(remaining):
            return .mustWait(remaining)
        case .stoppedBeforeEraseThreshold:
            return .stoppedBeforeEraseThreshold
        case let .finished(attempt):
            if case let .failure(error) = attempt.outcome {
                throw error
            }
            guard attempt.openedSlots.contains(index) else {
                return .wrong(reachesEraseThreshold: attempt.reachesEraseThreshold)
            }
            try await attemptCounter.reset()
            return .right
        }
    }

    private enum AttemptResult {
        case mustWait(Duration)
        case stoppedBeforeEraseThreshold
        case finished(Attempt)
    }

    /// Counts an attempt, runs it off the actor, and holds it to the deadline, raising the deadline if the attempt's
    /// work called for it.
    ///
    /// Throws `CancellationError` if the vault locked, or the task was cancelled, meanwhile. If the attempt `isRight`,
    /// the count is reset first, as it would be if the attempt had been wanted: left counted, a right tenth attempt
    /// would make the next one erase every vault (VAULT-34). That shows nothing an attempt that was wanted wouldn't,
    /// and it's the same for a real password and a duress one.
    private func attemptPassword(
        _ password: String,
        opensBody: Bool,
        stoppingBeforeEraseThreshold: Bool,
        lockEpoch: Int,
        isRight: (Attempt) -> Bool,
    ) async throws -> AttemptResult {
        // Before anything is counted. While an erase is underway the attempt is refused whatever the password, and a
        // right password could look wrong while the vault's key is wrapped with the device key: a wrong attempt
        // counts towards an erase.
        guard try await !deadlineStore.isErasing() else { throw VaultUnlockError.erasing }
        let state = try VaultStorageStateFile(directory: file.directory, fileSystem: file.fileSystem).read()
        if state.mode == .deviceKey, !state.isTurningThePasswordOffOrOn {
            throw VaultUnlockError.passwordIsOff
        }
        let deadline = try await min(deadlineStore.unlockDeadline(), Self.maximumDeadline)
        guard let contents = try await file.open() else { throw VaultUnlockError.noEncryptedVault }
        // A turn off or on that couldn't record how it ended. If the device key opens no slot, the vault is in the
        // password form, whatever the state says, so the attempt goes ahead: a full disk mustn't stop the password
        // unlocking once it's back on. If it opens one, a right password could look wrong, so it's refused.
        if state.isTurningThePasswordOffOrOn, try deviceKeyOpensASlot(of: contents) {
            throw VaultUnlockError.passwordChangeUnsettled
        }
        let reachesEraseThreshold: Bool
        switch try await attemptCounter.countAttempt(stoppingBeforeEraseThreshold: stoppingBeforeEraseThreshold) {
        case let .delayed(remaining):
            return .mustWait(remaining)
        case .stoppedBeforeEraseThreshold:
            return .stoppedBeforeEraseThreshold
        case let .counted(reaches):
            reachesEraseThreshold = reaches
        }
        let start = clock.now
        var attempt = await Task.detached(priority: .userInitiated) { [work] in
            Self.attempt(password: password, contents: contents, work: work, opensBody: opensBody)
        }.value
        attempt.reachesEraseThreshold = reachesEraseThreshold

        let raisedDeadline = attempt.workDuration.map { min($0 * Self.deadlineMultiplier, Self.maximumDeadline) }
        var heldUntil = deadline
        if let raisedDeadline, raisedDeadline > deadline, await isStillWanted(since: lockEpoch) {
            heldUntil = raisedDeadline
            // Raised before the wait, so the time it takes is inside the deadline. If saving it failed, the next slow
            // attempt raises it again.
            try? await deadlineStore.raiseUnlockDeadline(to: raisedDeadline)
        }
        // Cancelling cuts the wait short, and then the result is thrown away, so ending early reveals nothing.
        try? await clock.sleep(until: start.advanced(by: heldUntil))
        guard await isStillWanted(since: lockEpoch) else {
            if isRight(attempt) {
                try await attemptCounter.reset()
            }
            throw CancellationError()
        }
        return .finished(attempt)
    }

    /// Whether the device key opens any slot of the file. Only while a turn off or on is unsettled: it doesn't depend
    /// on the password.
    private func deviceKeyOpensASlot(of contents: VaultSlotFile) throws -> Bool {
        guard let key = try deviceKeyStore.deviceKey() else { return false }
        return VaultSlotFile.slotIndices.contains { (try? contents.openSlot($0, with: .device(key))) != nil }
    }

    private func isStillWanted(since lockEpoch: Int) async -> Bool {
        await session.lockEpoch == lockEpoch && !Task.isCancelled
    }

    private struct Attempt: Sendable {
        /// The thread CPU time deriving the key and trying the slots took, or `nil` if the key couldn't be derived.
        /// It's the same whatever the password.
        var workDuration: Duration?
        /// Every slot the password opened.
        var openedSlots: [Int] = []
        /// Whether, if the password was wrong, it made `AppLockPasswordAttemptCounter.eraseThreshold` or more wrong
        /// attempts in a row.
        var reachesEraseThreshold = false
        /// The slot that opened and the vault in it, `nil` if no slot opened (or no body was opened), or why the
        /// attempt failed.
        var outcome: Result<Opened?, any Error>
    }

    private struct Opened: Sendable {
        var slot: VaultSlotFile.OpenedSlot
        var state: VaultRecordState
    }

    /// Derives the key, tries every slot, and, if `opensBody`, opens one body. Runs off the actor, all on one thread.
    private static func attempt(
        password: String,
        contents: VaultSlotFile,
        work: any VaultUnlockWork,
        opensBody: Bool,
    ) -> Attempt {
        let start = work.threadCPUTime()
        let opened: [VaultSlotFile.OpenedSlot]
        do {
            let key = try work.passwordKey(for: password, header: contents.header)
            // Every slot, with no early exit. The key is released at the end of this scope.
            opened = VaultSlotFile.slotIndices.compactMap { work.openKeyBox($0, in: contents, with: key) }
        } catch {
            return Attempt(workDuration: nil, outcome: .failure(error))
        }
        let workDuration = work.threadCPUTime() - start
        let openedSlots = opened.map(\.index)
        guard opensBody else {
            return Attempt(workDuration: workDuration, openedSlots: openedSlots, outcome: .success(nil))
        }

        // The same password opening more than one slot means the newer vault was made with a password that happened
        // to open an older one too. The newer one is the one the user just made (see "Same passwords"). Wrap times
        // come from the clock of the device that wrapped the key, so one set wrong can make a newer vault look older.
        // Slots wrapped in the same millisecond go to the lowest index.
        guard let chosen = opened.max(by: { $0.wrappedAt < $1.wrappedAt }) else {
            // A wrong password opens a body too, so every attempt does the same work. The throwaway key fails to
            // authenticate it.
            _ = try? work.openBody(of: decoySlot(in: contents), in: contents)
            return Attempt(workDuration: workDuration, openedSlots: openedSlots, outcome: .success(nil))
        }
        let outcome = Result<Opened?, any Error> {
            try Opened(slot: chosen, state: work.openBody(of: chosen, in: contents))
        }
        return Attempt(workDuration: workDuration, openedSlots: openedSlots, outcome: outcome)
    }

    /// A random slot, as if opened with a throwaway key: opening its body does the work of opening a real one, and
    /// fails.
    private static func decoySlot(in file: VaultSlotFile) -> VaultSlotFile.OpenedSlot {
        let index = Int.random(in: VaultSlotFile.slotIndices)
        return VaultSlotFile.OpenedSlot(
            index: index,
            generation: 0,
            wrappedAtMilliseconds: 0,
            slotNonce: file.slotNonce(index),
            wrapKey: SymmetricKey(size: .bits256),
            dataKey: SymmetricKey(size: .bits256),
            bodyLength: file.header.slotSize - VaultSlotFile.bodyOffset,
        )
    }
}

// MARK: - The device key

extension VaultUnlockService {
    /// Opens the vault the device key wraps, while the App Lock Password is off (the `deviceKey` mode), and switches
    /// the store session to it.
    ///
    /// Device authentication, which the app lock asks for first, is all it takes. With no password to guess there's
    /// no attempt to count and no deadline to hold to.
    ///
    /// - Throws: `VaultUnlockError.noDeviceKey`, or `.deviceKeyOpensNoVault` if no slot opens with it. In an app
    ///   extension, `.deviceKeyNotInUse` if the vault isn't stored with the device key now.
    public func unlockWithDeviceKey() async throws {
        try await unlockWithDeviceKey(toChange: true)
    }

    /// Opens the vault the device key wraps only to show it, as a widget or the app's QuickType sync does: reading the
    /// file without its lock, and leaving nothing behind, not even a wrap stamp. Writes throw
    /// `VaultStoreSessionError.locked`.
    ///
    /// - Throws: As `unlockWithDeviceKey()`.
    func openWithDeviceKeyToShow() async throws {
        try await unlockWithDeviceKey(toChange: false)
    }

    /// - Parameter toChange: Whether the vault is opened to change it too, rather than only to show it.
    private func unlockWithDeviceKey(toChange: Bool) async throws {
        guard !isUnlocking else { throw VaultUnlockError.attemptUnderway }
        isUnlocking = true
        defer { isUnlocking = false }
        guard await session.isLocked else { throw VaultUnlockError.notLocked }
        guard try await !deadlineStore.isErasing() else { throw VaultUnlockError.erasing }
        // In an extension, nothing is read unless the vault is stored with the device key, and the vault is checked
        // again on every call once it's open.
        let accessGuard = accessGuard(openedIn: .deviceKey, allowsWrites: toChange)
        guard accessGuard?.isStillOpen ?? true else { throw VaultUnlockError.deviceKeyNotInUse }
        let lockEpoch = await session.lockEpoch

        guard let key = try deviceKeyStore.deviceKey() else { throw VaultUnlockError.noDeviceKey }
        var deviceKeyFile = file
        deviceKeyFile.protection = EncryptedVaultFile.protection(for: .deviceKey)
        let read = toChange ? try await deviceKeyFile.open() : try deviceKeyFile.readWithoutTheLock()
        guard let contents = read else { throw VaultUnlockError.noEncryptedVault }
        let opened = VaultSlotFile.slotIndices.compactMap { try? contents.openSlot($0, with: .device(key)) }
        guard let chosen = opened.max(by: { $0.wrappedAt < $1.wrappedAt }) else {
            throw VaultUnlockError.deviceKeyOpensNoVault
        }
        let state = try EncryptedVaultPayload.decode(slot: chosen, in: contents)
        if toChange {
            // As a password unlock does. The stamp is readable only while the device is unlocked, which it may not be.
            await noteUse(of: deviceKeyFile, wrappedAt: chosen.wrappedAt, openedIn: .deviceKey)
        }
        let store = EncryptedVaultStore(
            file: deviceKeyFile,
            slot: chosen,
            state: state,
            work: work,
            wrapStamper: wrapStamper,
            memoryCheck: writeMemoryCheck,
            accessGuard: toChange
                ? accessGuard
                : VaultAccessGuard(
                    openedIn: .deviceKey,
                    currentMode: currentAccessMode ?? { .deviceKey },
                    allowsWrites: false,
                ),
        )
        guard await session.switchTo(.unlocked(store), unlessLockedSince: lockEpoch) else {
            throw CancellationError()
        }
    }
}

// MARK: - Locking

extension VaultUnlockService {
    /// Locks the vault: waits for any change underway to finish saving, switches the store session to `locked`, and
    /// purges what the app read from the vault. An unlock attempt that's underway is thrown away.
    ///
    /// Once the session is locked, nothing holds the vault's store any more, and its keys are zeroed as it's
    /// released.
    public func lock() async {
        await session.lock()
        await purgeVaultContents()
    }
}

// MARK: - Memory

extension VaultUnlockService {
    /// Whether this process has the memory to unlock: the key derivation's working memory, the file, and a 16 MiB
    /// margin.
    ///
    /// The AutoFill extension checks this before it asks for the password, and tells the user to open Vault instead
    /// if there isn't enough (VAULT-49). The app can always unlock.
    public func hasMemoryHeadroomToUnlock() throws -> Bool {
        guard let (header, fileSize) = try file.readHeader() else { throw VaultUnlockError.noEncryptedVault }
        let needed = Int(header.kdfParameters.memoryKiB) * 1024 + fileSize + Self.memoryMargin
        guard let available = availableMemory() else { return true }
        return available >= needed
    }

    /// The memory this process can still use before the system stops it, or `nil` if it has no limit.
    ///
    /// On an iPhone every app and extension has a limit, and `os_proc_available_memory()` gives 0 once it's over
    /// it. The simulator and other platforms have none.
    static let processAvailableMemory: @Sendable () -> Int? = {
        #if os(iOS) && !targetEnvironment(simulator)
        Int(os_proc_available_memory())
        #else
        nil
        #endif
    }
}
