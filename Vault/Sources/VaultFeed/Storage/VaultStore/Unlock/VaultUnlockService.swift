import CryptoKit
import Foundation
#if os(iOS)
import os
#endif

/// Unlocks the encrypted vault with the app lock password, and locks it again.
///
/// **Unlocking** (`unlock(password:)`):
///
/// 1. Counts the attempt with `AppLockPasswordAttemptCounter`, before anything is derived. If the user has to wait
///    after their last wrong attempts, it says how long, and tries nothing.
/// 2. Starts the device's unlock deadline.
/// 3. Derives `K_pw` from the password with Argon2id, off this actor.
/// 4. Tries every slot's key box, with no early exit.
/// 5. Opens one body: the slot that opened, or the most recently wrapped if more than one did. If none did, it opens
///    a decoy instead, a random slot's body with a throwaway key, which fails.
/// 6. Drops `K_pw` and the wrap keys it didn't keep. They're `SymmetricKey`s, which are zeroed when released.
/// 7. Waits for the deadline. Then it resets the count and switches the store session to the vault, or reports a
///    wrong password.
///
/// So real, duress and wrong passwords do the same work, and finish at the same deadline. The deadline is set when
/// the vault is created, at 1.5 times the derivation calibration expected. If a derivation takes longer than it, for
/// example after a restore onto a slower iPhone, the deadline is raised to 1.5 times that derivation, for that
/// attempt and every later one. It's never lowered.
///
/// **Locking** (`lock()`) waits for any change already underway to finish saving, switches the store session to
/// `locked`, and purges what the app read from the vault.
///
/// See "Unlocking and locking" in `docs/on-device-encryption.md`. Never log, print or measure anything about the
/// password or which vault opened.
public actor VaultUnlockService {
    /// The memory the AutoFill extension keeps free on top of the key derivation's and the file's.
    static let memoryMargin = 16 << 20
    /// A derivation that takes longer than the deadline raises it to this multiple of the derivation.
    static let deadlineMultiplier = 1.5

    private let file: EncryptedVaultFile
    private let session: VaultStoreSession
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let deadlineStore: any VaultUnlockDeadlineStoring
    private let purgeVaultContents: @Sendable () async -> Void
    private let clock: any VaultUnlockClock
    private let work: any VaultUnlockWork
    private let availableMemory: @Sendable () -> Int

    private var isUnlocking = false
    /// Counts locks. An attempt that was underway when the vault locked is thrown away.
    private var lockGeneration = 0

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

    init(
        file: EncryptedVaultFile,
        session: VaultStoreSession,
        attemptCounter: AppLockPasswordAttemptCounter,
        deadlineStore: any VaultUnlockDeadlineStoring,
        purgeVaultContents: @escaping @Sendable () async -> Void,
        clock: any VaultUnlockClock = ContinuousClock(),
        work: any VaultUnlockWork = LiveVaultUnlockWork(),
        availableMemory: @escaping @Sendable () -> Int = VaultUnlockService.processAvailableMemory,
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
        let generation = lockGeneration

        let deadline = try await deadlineStore.unlockDeadline()
        guard let contents = try await file.open() else { throw VaultUnlockError.noEncryptedVault }
        // The erase after too many wrong attempts (VAULT-52) will use `reachesEraseThreshold`.
        if case let .delayed(remaining) = try await attemptCounter.countAttempt() {
            return .mustWait(remaining)
        }
        let start = clock.now
        let attempt = await Task.detached(priority: .userInitiated) { [work, clock] in
            Self.attempt(password: password, contents: contents, work: work, clock: clock)
        }.value

        let heldUntil = max(deadline, attempt.derivationDuration * Self.deadlineMultiplier)
        if heldUntil > deadline {
            // This attempt waits for the raised deadline either way, and if saving it failed, the next one raises it
            // again.
            try? await deadlineStore.raiseUnlockDeadline(to: heldUntil)
        }
        // Cancelling cuts the wait short, and then the result is thrown away, so ending early reveals nothing.
        try? await clock.sleep(until: start.advanced(by: heldUntil))
        try requireStillWanted(since: generation)

        switch attempt.outcome {
        case .success(nil):
            return .wrongPassword
        case let .success(opened?):
            try await attemptCounter.reset()
            try requireStillWanted(since: generation)
            await session.switchTo(.unlocked(EncryptedVaultStore(file: file, slot: opened.slot, state: opened.state)))
            if generation != lockGeneration {
                // The vault locked while the session was switching: that lock wins.
                await session.lock()
                throw CancellationError()
            }
            return .unlocked
        case let .failure(error):
            throw error
        }
    }

    private func requireStillWanted(since generation: Int) throws {
        guard generation == lockGeneration, !Task.isCancelled else { throw CancellationError() }
    }

    /// The bytes a password derives its key from: its UTF-8, in Unicode's composed form (NFC), so it derives the
    /// same key however the keyboard put its accents together. Setting a password must use the same.
    static func keyMaterial(for password: String) -> Data {
        Data(password.precomposedStringWithCanonicalMapping.utf8)
    }

    private struct Attempt: Sendable {
        var derivationDuration: Duration
        /// The slot that opened and the vault in it, `nil` if no slot opened, or why the attempt failed.
        var outcome: Result<Opened?, any Error>
    }

    private struct Opened: Sendable {
        var slot: VaultSlotFile.OpenedSlot
        var state: VaultRecordState
    }

    /// Derives the key, tries every slot, and opens one body. Runs off the actor.
    private static func attempt(
        password: String,
        contents: VaultSlotFile,
        work: any VaultUnlockWork,
        clock: any VaultUnlockClock,
    ) -> Attempt {
        let start = clock.now
        let opened: [VaultSlotFile.OpenedSlot]
        do {
            var keyMaterial = keyMaterial(for: password)
            defer { SlotRandom.wipe(&keyMaterial) }
            let key = try work.passwordKey(for: keyMaterial, header: contents.header)
            // Every slot, with no early exit. The key is released at the end of this scope.
            opened = VaultSlotFile.slotIndices.compactMap { work.openKeyBox($0, in: contents, with: key) }
        } catch {
            return Attempt(derivationDuration: start.duration(to: clock.now), outcome: .failure(error))
        }
        let derivationDuration = start.duration(to: clock.now)

        // The same password opening more than one slot means the newer vault was made with a password that happened
        // to open an older one too. The newer one is the one the user just made (see "Same passwords").
        guard let chosen = opened.max(by: { $0.wrappedAt < $1.wrappedAt }) else {
            // A wrong password opens a body too, so every attempt does the same work. The throwaway key fails to
            // authenticate it.
            _ = try? work.openBody(of: decoySlot(in: contents), in: contents)
            return Attempt(derivationDuration: derivationDuration, outcome: .success(nil))
        }
        let outcome = Result<Opened?, any Error> {
            try Opened(slot: chosen, state: work.openBody(of: chosen, in: contents))
        }
        return Attempt(derivationDuration: derivationDuration, outcome: outcome)
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
        lockGeneration += 1
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
    public func hasMemoryHeadroomToUnlock() async throws -> Bool {
        let needed = try await memoryNeededToUnlock()
        let available = availableMemory()
        // No figure at all means the process has no memory limit, as in the simulator.
        return available == 0 || available >= needed
    }

    /// Read in its own scope, so the file read to find out is released before the memory left is measured.
    private func memoryNeededToUnlock() async throws -> Int {
        guard let contents = try await file.open() else { throw VaultUnlockError.noEncryptedVault }
        return Int(contents.header.kdfParameters.memoryKiB) * 1024 + contents.bytes.count + Self.memoryMargin
    }

    /// The memory this process can still use before the system stops it, or 0 if there's no limit.
    static let processAvailableMemory: @Sendable () -> Int = {
        #if os(iOS)
        Int(os_proc_available_memory())
        #else
        0
        #endif
    }
}
