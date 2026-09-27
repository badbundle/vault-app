import Foundation

/// How the AutoFill extension opens the encrypted vault, in its own process: with the App Lock Password while it's on,
/// or with the device key while it's off. VAULT-46's `VaultUnlockService`, with the device's attempt counter and
/// unlock deadline.
///
/// - **The same attempts as the app.** A password is counted with the same keychain counter as the app, so a guess in
///   AutoFill waits, and counts toward an erase, just as one on the lock screen does.
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
public final class AutofillVaultService: AppLockPasswordService {
    /// Thrown by `unlock(password:)` and `openWithDeviceKey()` when there isn't the memory. Nothing was counted or
    /// opened.
    public struct NotEnoughMemoryError: Error, Equatable {
        public init() {}
    }

    /// Called when an unlock, an open or a save doesn't go ahead for want of memory.
    public var onNotEnoughMemory: (@MainActor () -> Void)? {
        get { memoryNotifier.handler }
        set { memoryNotifier.handler = newValue }
    }

    private let unlockService: VaultUnlockService
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let memoryNotifier: MemoryNotifier
    private let needsPassword: @Sendable () -> Bool

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
            needsPassword: { Self.needsPassword(stateFile: stateFile) },
        )
    }

    init(
        file: EncryptedVaultFile,
        session: VaultStoreSession,
        attemptCounter: AppLockPasswordAttemptCounter,
        deadlineStore: any VaultUnlockDeadlineStoring,
        deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore(),
        purgeVaultContents: @escaping @Sendable () async -> Void,
        needsPassword: @escaping @Sendable () -> Bool,
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
            deviceKeyStore: deviceKeyStore,
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
        self.needsPassword = needsPassword
        self.memoryNotifier = memoryNotifier
    }

    /// Whether only the App Lock Password opens the vault, as the storage state says now: whenever it doesn't open
    /// without one. That includes a change underway, or a state that can't be read, when nothing may open it on device
    /// authentication alone. Read afresh each time, since the app can turn the password on or off while the
    /// extension's process lives on.
    public var isPasswordSet: Bool {
        needsPassword()
    }

    nonisolated static func needsPassword(stateFile: VaultStorageStateFile) -> Bool {
        !VaultAccessMode(state: try? stateFile.read()).opensWithoutPassword
    }

    public func remainingDelay() async throws -> Duration {
        try await attemptCounter.remainingDelay()
    }

    /// Tries the password, once there's the memory to derive its key.
    ///
    /// - Throws: `NotEnoughMemoryError` without counting the attempt, if there isn't the memory.
    public func unlock(password: String) async throws -> AppLockPasswordResult {
        try await requireMemoryHeadroom()
        return switch try await unlockService.unlock(password: password) {
        case .unlocked: .accepted
        case .wrongPassword: .wrong
        case let .mustWait(remaining): .delayed(remaining)
        }
    }

    /// Opens the vault with the device key, while the password is off, once there's the memory to read it. Nothing's
    /// counted: device authentication, which the sheet asks for first if the app lock is on, is all it takes.
    ///
    /// - Throws: `NotEnoughMemoryError` if there isn't the memory, or as `VaultUnlockService.unlockWithDeviceKey()`.
    public func openWithDeviceKey() async throws {
        try await requireMemoryHeadroom()
        try await unlockService.unlockWithDeviceKey()
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

    /// Whether the extension has the memory to open the vault: to derive a password's key, or read the file with the
    /// device key and decode it, which takes less. The sheet asks before it offers anything, and each unlock or open
    /// asks again.
    public func hasMemoryHeadroomToUnlock() async throws -> Bool {
        try await unlockService.hasMemoryHeadroomToUnlock()
    }

    /// Locks the vault again, if it's open: its keys and everything read from it go.
    public func lockVault() async {
        await unlockService.lock()
    }

    private func requireMemoryHeadroom() async throws {
        guard try await unlockService.hasMemoryHeadroomToUnlock() else {
            memoryNotifier.notify()
            throw NotEnoughMemoryError()
        }
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

extension VaultStoreSession {
    /// A session with the vault the device key opens, for the widget extension, while the App Lock Password is off.
    ///
    /// As in AutoFill, it never writes the storage state, and each save that replaces the file checks there's the
    /// memory for it first. A widget has less to spare than AutoFill, so an increment it can't afford throws
    /// `EncryptedVaultStoreError.notEnoughMemory` rather than getting the extension stopped.
    ///
    /// - Throws: As `VaultUnlockService.unlockWithDeviceKey()`, such as while the device is locked after starting up.
    public static func openedWithDeviceKey(directory: URL) async throws -> VaultStoreSession {
        let session = VaultStoreSession(target: .locked)
        let stateFile = VaultStorageStateFile(directory: directory)
        let availableMemory = VaultUnlockService.processAvailableMemory
        let unlockService = VaultUnlockService(
            file: EncryptedVaultFile(directory: directory),
            session: session,
            attemptCounter: AppLockPasswordAttemptCounter(),
            deadlineStore: ReadOnlyUnlockDeadlineStore(stateFile: stateFile),
            purgeVaultContents: {},
            availableMemory: availableMemory,
            wrapStamper: VaultDeviceWrapStamper(),
            writeMemoryCheck: VaultWriteMemoryCheck(availableMemory: availableMemory) {},
        )
        try await unlockService.unlockWithDeviceKey()
        return session
    }
}
