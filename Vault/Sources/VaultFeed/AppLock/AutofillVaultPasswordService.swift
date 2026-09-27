import Foundation

/// The App Lock Password as the AutoFill extension unlocks the encrypted vault with it, in its own process: VAULT-46's
/// `VaultUnlockService`, with the device's attempt counter and unlock deadline.
///
/// - **The same attempts as the app.** It counts with the same keychain counter as the app, so a guess in AutoFill
///   waits, and counts toward an erase, just as one on the lock screen does.
/// - **Memory.** An extension the system stops for using too much memory has still counted the attempt, as a wrong
///   one. So each unlock checks there's the memory to derive the key first, and each save that replaces the vault
///   file checks there's the memory for that (`VaultWriteMemoryCheck`). When there isn't, it calls
///   `onNotEnoughMemory`, so the sheet can send the user to Vault, and nothing is counted, derived or written.
/// - **Read-only storage state.** Only the app writes the storage state, so this never raises the unlock deadline,
///   however long an attempt takes.
///
/// Setting, changing and turning off the password, and making a duress vault, are only for the app's Settings, so here
/// they throw.
@MainActor
public final class AutofillVaultPasswordService: AppLockPasswordService {
    /// Thrown by `unlock(password:)` when there isn't the memory to derive the key. Nothing was counted.
    public struct NotEnoughMemoryError: Error, Equatable {}

    public let isPasswordSet: Bool
    /// Called when an unlock or a save doesn't go ahead for want of memory.
    public var onNotEnoughMemory: (@MainActor () -> Void)? {
        get { memoryNotifier.handler }
        set { memoryNotifier.handler = newValue }
    }

    private let unlockService: VaultUnlockService
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let memoryNotifier: MemoryNotifier

    /// - Parameters:
    ///   - directory: The vault's storage directory, with the encrypted file and the storage state in it.
    ///   - session: The store session the extension reads and writes the vault through.
    ///   - purgeVaultContents: Forgets everything the extension read from the vault. Called every time it locks.
    public convenience init(
        directory: URL,
        session: VaultStoreSession,
        purgeVaultContents: @escaping @Sendable () async -> Void,
    ) {
        let stateFile = VaultStorageStateFile(directory: directory)
        self.init(
            file: EncryptedVaultFile(directory: directory),
            session: session,
            attemptCounter: AppLockPasswordAttemptCounter(),
            deadlineStore: ReadOnlyUnlockDeadlineStore(stateFile: stateFile),
            purgeVaultContents: purgeVaultContents,
            isPasswordSet: Self.isPasswordSet(stateFile: stateFile),
        )
    }

    init(
        file: EncryptedVaultFile,
        session: VaultStoreSession,
        attemptCounter: AppLockPasswordAttemptCounter,
        deadlineStore: any VaultUnlockDeadlineStoring,
        purgeVaultContents: @escaping @Sendable () async -> Void,
        isPasswordSet: Bool,
        clock: any VaultUnlockClock = ContinuousClock(),
        work: any VaultUnlockWork = LiveVaultUnlockWork(),
        availableMemory: @escaping @Sendable () -> Int? = VaultUnlockService.processAvailableMemory,
        wrapStamper: VaultDeviceWrapStamper = VaultDeviceWrapStamper(),
    ) {
        let memoryNotifier = MemoryNotifier()
        unlockService = VaultUnlockService(
            file: file,
            session: session,
            attemptCounter: attemptCounter,
            deadlineStore: deadlineStore,
            purgeVaultContents: purgeVaultContents,
            clock: clock,
            work: work,
            availableMemory: availableMemory,
            wrapStamper: wrapStamper,
            writeMemoryCheck: VaultWriteMemoryCheck(availableMemory: availableMemory) {
                Task { @MainActor in
                    memoryNotifier.notify()
                }
            },
        )
        self.attemptCounter = attemptCounter
        self.isPasswordSet = isPasswordSet
        self.memoryNotifier = memoryNotifier
    }

    /// Whether the password is set, as far as the extension goes: whenever the vault isn't plain. That includes a
    /// conversion underway, or a state that can't be read, when the vault can't be opened without the password either.
    static func isPasswordSet(stateFile: VaultStorageStateFile) -> Bool {
        !((try? stateFile.read().isPlain) ?? false)
    }

    public func remainingDelay() async throws -> Duration {
        try await attemptCounter.remainingDelay()
    }

    /// Tries the password, once there's the memory to derive its key.
    ///
    /// - Throws: `NotEnoughMemoryError` without counting the attempt, if there isn't the memory.
    public func unlock(password: String) async throws -> AppLockPasswordResult {
        guard try await unlockService.hasMemoryHeadroomToUnlock() else {
            memoryNotifier.notify()
            throw NotEnoughMemoryError()
        }
        return switch try await unlockService.unlock(password: password) {
        case .unlocked: .accepted
        case .wrongPassword: .wrong
        case let .mustWait(remaining): .delayed(remaining)
        }
    }

    public func setPassword(_: String) async throws {
        throw AppLockPasswordUnavailableError()
    }

    public func changePassword(current _: String, new _: String) async throws -> AppLockPasswordResult {
        throw AppLockPasswordUnavailableError()
    }

    public func turnOffPassword(current _: String) async throws -> AppLockPasswordResult {
        throw AppLockPasswordUnavailableError()
    }

    public func makeDuressVault(password _: String) async throws {
        throw AppLockPasswordUnavailableError()
    }

    /// Whether the extension has the memory to derive the key and open the vault. The sheet asks before it offers the
    /// password, and `unlock(password:)` asks again before it counts the attempt.
    public func hasMemoryHeadroomToUnlock() async throws -> Bool {
        try await unlockService.hasMemoryHeadroomToUnlock()
    }

    /// Locks the vault again, if it's open: its keys and everything read from it go.
    public func lockVault() async {
        await unlockService.lock()
    }
}

/// Passes on "not enough memory" to whoever's listening now, from wherever it's found.
@MainActor
private final class MemoryNotifier {
    var handler: (@MainActor () -> Void)?

    func notify() {
        handler?()
    }
}

/// The device's unlock deadline for a process that mustn't write the storage state: an app extension. It never raises
/// the deadline, however long an attempt takes. Only the app does.
struct ReadOnlyUnlockDeadlineStore: VaultUnlockDeadlineStoring {
    let stateFile: VaultStorageStateFile

    func unlockDeadline() async throws -> Duration {
        try await stateFile.unlockDeadline()
    }

    func raiseUnlockDeadline(to _: Duration) async throws {}

    func isErasing() async throws -> Bool {
        try await stateFile.isErasing()
    }
}
