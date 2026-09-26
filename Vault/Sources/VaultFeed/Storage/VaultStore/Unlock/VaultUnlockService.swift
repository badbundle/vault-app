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
/// 7. Waits for the deadline. Then it resets the count and switches the store session to the vault, or reports a
///    wrong password.
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
    private let purgeVaultContents: @Sendable () async -> Void
    private let clock: any VaultUnlockClock
    private let work: any VaultUnlockWork
    private let availableMemory: @Sendable () -> Int?

    private var isUnlocking = false

    /// - Parameters:
    ///   - directory: The directory the encrypted vault file is in.
    ///   - session: The store session the app reads and writes the vault through.
    ///   - attemptCounter: Counts every attempt before it's tried, and is reset when one opens a vault.
    ///   - purgeVaultContents: Forgets everything the app read from the vault. Called every time it locks.
    public init(
        directory: URL,
        session: VaultStoreSession,
        attemptCounter: AppLockPasswordAttemptCounter,
        deadlineStore: any VaultUnlockDeadlineStoring,
        purgeVaultContents: @escaping @Sendable () async -> Void,
    ) {
        self.init(
            file: EncryptedVaultFile(directory: directory),
            session: session,
            attemptCounter: attemptCounter,
            deadlineStore: deadlineStore,
            purgeVaultContents: purgeVaultContents,
        )
    }

    /// - Parameter availableMemory: The memory the process can still use, or `nil` if it has no limit.
    init(
        file: EncryptedVaultFile,
        session: VaultStoreSession,
        attemptCounter: AppLockPasswordAttemptCounter,
        deadlineStore: any VaultUnlockDeadlineStoring,
        purgeVaultContents: @escaping @Sendable () async -> Void,
        clock: any VaultUnlockClock = ContinuousClock(),
        work: any VaultUnlockWork = LiveVaultUnlockWork(),
        availableMemory: @escaping @Sendable () -> Int? = VaultUnlockService.processAvailableMemory,
    ) {
        self.file = file
        self.session = session
        self.attemptCounter = attemptCounter
        self.deadlineStore = deadlineStore
        self.purgeVaultContents = purgeVaultContents
        self.clock = clock
        self.work = work
        self.availableMemory = availableMemory
    }
}

/// How an attempt to unlock with the app lock password turned out.
public enum VaultUnlockResult: Equatable, Sendable {
    /// A vault opened, and the store session now reads and writes it.
    case unlocked
    /// No vault opened with the password.
    case wrongPassword
    /// The user has to wait this long after their last wrong attempts before trying again. Nothing was tried.
    case mustWait(Duration)
}

public enum VaultUnlockError: Error, Equatable, Sendable {
    /// There's no encrypted vault file to unlock.
    case noEncryptedVault
    /// Another attempt is still underway.
    case attemptUnderway
    /// The store session isn't locked: a vault is open already.
    case notLocked
}

// MARK: - Unlocking

extension VaultUnlockService {
    /// Tries the password, and if it opens a vault, switches the store session to it.
    ///
    /// Once the attempt is counted, it returns at the device's unlock deadline whatever happens, and throws only
    /// then: for example if the password opened a vault that can't be read.
    ///
    /// - Throws: `VaultUnlockError`, an error counting the attempt or reading the file, or `CancellationError` if the
    ///   vault locked, or the task was cancelled, while the attempt was underway. Its result is thrown away then.
    public func unlock(password: String) async throws -> VaultUnlockResult {
        guard !isUnlocking else { throw VaultUnlockError.attemptUnderway }
        isUnlocking = true
        defer { isUnlocking = false }
        guard await session.isLocked else { throw VaultUnlockError.notLocked }
        let lockEpoch = await session.lockEpoch

        let deadline = try await min(deadlineStore.unlockDeadline(), Self.maximumDeadline)
        guard let contents = try await file.open() else { throw VaultUnlockError.noEncryptedVault }
        // The erase after too many wrong attempts (VAULT-52) will use `reachesEraseThreshold`.
        if case let .delayed(remaining) = try await attemptCounter.countAttempt() {
            return .mustWait(remaining)
        }
        let start = clock.now
        let attempt = await Task.detached(priority: .userInitiated) { [work] in
            Self.attempt(password: password, contents: contents, work: work)
        }.value

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
        guard await isStillWanted(since: lockEpoch) else { throw CancellationError() }

        switch attempt.outcome {
        case .success(nil):
            return .wrongPassword
        case let .success(opened?):
            try await attemptCounter.reset()
            let store = EncryptedVaultStore(file: file, slot: opened.slot, state: opened.state, work: work)
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

    private func isStillWanted(since lockEpoch: Int) async -> Bool {
        await session.lockEpoch == lockEpoch && !Task.isCancelled
    }

    private struct Attempt: Sendable {
        /// The thread CPU time deriving the key and trying the slots took, or `nil` if the key couldn't be derived.
        /// It's the same whatever the password.
        var workDuration: Duration?
        /// The slot that opened and the vault in it, `nil` if no slot opened, or why the attempt failed.
        var outcome: Result<Opened?, any Error>
    }

    private struct Opened: Sendable {
        var slot: VaultSlotFile.OpenedSlot
        var state: VaultRecordState
    }

    /// Derives the key, tries every slot, and opens one body. Runs off the actor, all on one thread.
    private static func attempt(password: String, contents: VaultSlotFile, work: any VaultUnlockWork) -> Attempt {
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

        // The same password opening more than one slot means the newer vault was made with a password that happened
        // to open an older one too. The newer one is the one the user just made (see "Same passwords"). Wrap times
        // come from the clock of the device that wrapped the key, so one set wrong can make a newer vault look older.
        // Slots wrapped in the same millisecond go to the lowest index.
        guard let chosen = opened.max(by: { $0.wrappedAt < $1.wrappedAt }) else {
            // A wrong password opens a body too, so every attempt does the same work. The throwaway key fails to
            // authenticate it.
            _ = try? work.openBody(of: decoySlot(in: contents), in: contents)
            return Attempt(workDuration: workDuration, outcome: .success(nil))
        }
        let outcome = Result<Opened?, any Error> {
            try Opened(slot: chosen, state: work.openBody(of: chosen, in: contents))
        }
        return Attempt(workDuration: workDuration, outcome: outcome)
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
