import Foundation

/// How the AutoFill extension opens the encrypted vault, in its own process: with the App Lock Password while it's on,
/// or with the device key while it's off. VAULT-46's `VaultUnlockService`, with the device's attempt counter and
/// unlock deadline.
///
/// - **The same attempts as the app.** A password is counted with the same keychain counter as the app, so a guess in
///   AutoFill waits, and counts toward an erase, just as one on the lock screen does.
/// - **It never erases** (VAULT-34). It doesn't try or count an attempt that would make
///   `AppLockPasswordAttemptCounter.eraseThreshold` or more wrong ones in a row, whether erasing after failed
///   passwords is on or off, and answers `.onlyAtTheLockScreen`, so the sheet sends the user to Vault. An erase is
///   a run of file and keychain steps the system could stop an extension in the middle of, while the app finishes
///   the same erase at launch, so only the app erases. The count is held against the app while it's decided, so an
///   attempt the app makes at the same moment can't make this one the tenth.
/// - **Memory.** An extension the system stops for using too much memory has still counted the attempt, as a wrong
///   one. So each unlock checks there's the memory to derive the key first, and each save that replaces the vault
///   file checks there's the memory for that (`VaultWriteMemoryCheck`). When there isn't, it calls
///   `onNotEnoughMemory`, so the sheet can send the user to Vault, and nothing is counted, derived or written.
/// - **Read-only storage state.** Only the app writes the storage state, so this never raises the unlock deadline,
///   however long an attempt takes.
/// - **The vault as it's stored now.** The app can turn the password on or off, or erase the vault, while the sheet is
///   open. The device key opens nothing unless the storage state says it's in use, and every call to an open vault
///   checks the vault is still stored the way it was when it opened (`VaultAccessGuard`).
///
/// Setting, changing and turning off the password, making a duress vault, and turning erasing on or off, are only for
/// the app's Settings, so here they throw.
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
    private let settings: AppLockSettingsStore
    private let memoryNotifier: MemoryNotifier
    private let needsPassword: @Sendable () -> Bool

    /// - Parameters:
    ///   - directory: The vault's storage directory, with the encrypted file and the storage state in it.
    ///   - session: The store session the extension reads and writes the vault through.
    ///   - settings: The app lock's settings, with erasing after failed passwords.
    ///   - purgeVaultContents: Forgets everything the extension read from the vault. Called every time it locks.
    public convenience init(
        directory: URL,
        session: VaultStoreSession,
        settings: AppLockSettingsStore,
        purgeVaultContents: @escaping @Sendable () async -> Void,
    ) {
        let stateFile = VaultStorageStateFile(directory: directory)
        self.init(
            file: EncryptedVaultFile(directory: directory),
            session: session,
            attemptCounter: AppLockPasswordAttemptCounter(),
            deadlineStore: ReadOnlyUnlockDeadlineStore(stateFile: stateFile),
            settings: settings,
            purgeVaultContents: purgeVaultContents,
            needsPassword: { Self.needsPassword(stateFile: stateFile) },
            currentAccessMode: VaultAccessMode.reader(directory: directory),
        )
    }

    init(
        file: EncryptedVaultFile,
        session: VaultStoreSession,
        attemptCounter: AppLockPasswordAttemptCounter,
        deadlineStore: any VaultUnlockDeadlineStoring,
        deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore(),
        settings: AppLockSettingsStore,
        purgeVaultContents: @escaping @Sendable () async -> Void,
        needsPassword: @escaping @Sendable () -> Bool,
        clock: any VaultUnlockClock = ContinuousClock(),
        work: any VaultUnlockWork = LiveVaultUnlockWork(),
        availableMemory: @escaping @Sendable () -> Int? = VaultUnlockService.processAvailableMemory,
        wrapStamper: VaultDeviceWrapStamper = VaultDeviceWrapStamper(),
        currentAccessMode: (@Sendable () -> VaultAccessMode)? = nil,
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
            currentAccessMode: currentAccessMode,
        )
        self.attemptCounter = attemptCounter
        self.settings = settings
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

    public var erasesAfterFailedPasswords: Bool {
        settings.erasesAfterFailedPasswords
    }

    public func remainingDelay() async throws -> Duration {
        try await attemptCounter.remainingDelay()
    }

    /// Tries the password, once there's the memory to derive its key, unless it's the attempt that could erase.
    ///
    /// - Returns: `.onlyAtTheLockScreen`, without trying or counting it, for an attempt that would make the erase
    ///   threshold's wrong password in a row, or while an erase is underway, which the app finishes.
    /// - Throws: `NotEnoughMemoryError` without counting the attempt, if there isn't the memory.
    public func unlock(password: String) async throws -> AppLockPasswordResult {
        try await requireMemoryHeadroom()
        let result: VaultUnlockResult
        do {
            result = try await unlockService.unlock(password: password, stoppingBeforeEraseThreshold: true)
        } catch VaultUnlockError.stoppedBeforeEraseThreshold, VaultUnlockError.erasing {
            return .onlyAtTheLockScreen
        }
        return switch result {
        case .unlocked: .accepted
        case .wrongPassword: .wrong
        case let .mustWait(remaining): .delayed(remaining)
        }
    }

    /// Opens the vault with the device key, while the password is off, once there's the memory to read it. Nothing's
    /// counted: device authentication, which the sheet asks for first if the app lock is on, is all it takes.
    ///
    /// - Throws: `NotEnoughMemoryError` if there isn't the memory, or as `VaultUnlockService.unlockWithDeviceKey()`,
    ///   including `VaultUnlockError.deviceKeyNotInUse` once the password's on again.
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

    public func setErasesAfterFailedPasswords(_: Bool, current _: String) async throws -> AppLockPasswordResult {
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
    /// A session with the vault the device key opens, only to show it, while the App Lock Password is off: for the
    /// widgets, QuickType requests, and filling QuickType again.
    ///
    /// It reads the file without its lock, and leaves nothing behind: no lock file, no wrap stamp, and no change to
    /// the storage state. Writes throw `VaultStoreSessionError.locked`. Every read checks the vault is still stored
    /// with the device key, and finds nothing once it isn't. Lock the session once it's read.
    ///
    /// - Throws: As `VaultUnlockService.unlockWithDeviceKey()`: `VaultUnlockError.deviceKeyNotInUse` unless the
    ///   vault's stored with the device key now, or an error such as while the device is locked after starting up.
    public static func openedToShowWithDeviceKey(directory: URL) async throws -> VaultStoreSession {
        try await openedToShowWithDeviceKey(
            file: EncryptedVaultFile(directory: directory),
            stateFile: VaultStorageStateFile(directory: directory),
            deviceKeyStore: VaultDeviceKeychainStore(),
            currentAccessMode: VaultAccessMode.reader(directory: directory),
        )
    }

    static func openedToShowWithDeviceKey(
        file: EncryptedVaultFile,
        stateFile: VaultStorageStateFile,
        deviceKeyStore: any VaultDeviceKeyStoring,
        currentAccessMode: @escaping @Sendable () -> VaultAccessMode,
    ) async throws -> VaultStoreSession {
        let session = VaultStoreSession(target: .locked)
        let unlockService = VaultUnlockService(
            file: file,
            session: session,
            attemptCounter: AppLockPasswordAttemptCounter(),
            deadlineStore: ReadOnlyUnlockDeadlineStore(stateFile: stateFile),
            deviceKeyStore: deviceKeyStore,
            purgeVaultContents: {},
            wrapStamper: VaultDeviceWrapStamper(),
            currentAccessMode: currentAccessMode,
        )
        try await unlockService.openWithDeviceKeyToShow()
        return session
    }

    /// Reads everything in the session `open` opens, then locks it, whatever happens: for a vault opened only to read
    /// it once (`openedToShowWithDeviceKey(directory:)`).
    public static func retrieveAndLock(
        query: VaultStoreQuery = .init(),
        from open: @Sendable () async throws -> VaultStoreSession,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        let session = try await open()
        do {
            let result = try await session.retrieve(query: query)
            await session.lock()
            return result
        } catch {
            await session.lock()
            throw error
        }
    }
}
