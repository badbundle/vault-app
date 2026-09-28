import Foundation

/// The App Lock Password in the app, on the vault's storage:
///
/// - **Unlocking** with the password (`VaultUnlockService`, VAULT-46), through `AppLockPasswordUnlocker`, which
///   erases every vault after too many wrong ones when the user has turned that on (VAULT-34). Or with device
///   authentication alone while the password is off after being on (the `deviceKey` mode).
/// - **Setting it** by converting the plain store into an encrypted vault (`VaultEncryptionConverter`, VAULT-47), or
///   turning it back on after it was turned off.
/// - **Changing it and turning it off** (`VaultPasswordChangeService`, VAULT-48).
/// - **Making a duress vault** from the open vault (VAULT-51).
/// - **Turning erasing after failed passwords on or off** (VAULT-34), which setting, turning off and turning the
///   password back on all turn off.
///
/// It follows how the vault is stored as those change it, so the lock knows whether to ask for the password. It maps
/// their results one to one, and passes their errors through.
///
/// The AutoFill extension has its own (`AutofillVaultService`): it only unlocks.
@MainActor
public final class EncryptedVaultPasswordService: AppLockPasswordService {
    /// How the vault is stored now: as launch recovery left it, then as this changes it.
    public private(set) var mode: VaultStorageState.Mode

    private let session: VaultStoreSession
    private let unlockService: VaultUnlockService
    private let unlocker: AppLockPasswordUnlocker
    private let changeService: VaultPasswordChangeService
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let settings: AppLockSettingsStore
    private let stateFile: VaultStorageStateFile
    private let archives: any VaultStoreArchiving
    private let makeConverter: @MainActor () -> VaultEncryptionConverter?

    /// - Parameters:
    ///   - directory: The vault's storage directory.
    ///   - mode: How the vault is stored, as launch recovery left it.
    ///   - session: The store session the app reads and writes the vault through.
    ///   - settings: The app lock's settings, with erasing after failed passwords.
    ///   - erase: Erases every vault, and forgets what the app holds from them: `VaultRoot.eraseVault()`.
    ///   - archives: The copies of the plain store set aside because they couldn't be opened.
    ///   - deviceBackupSettings: The plain store's backup settings, which setting the password moves into the vault.
    ///   - purgeVaultContents: Forgets everything the app read from the vault. Called every time it locks.
    ///   - conversionHooks: What the app does around converting the plain store.
    ///   - passwordHooks: Brings the widgets, QuickType and AutoFill up to date with the password turned off or on.
    ///   - plainStore: The plain store while the vault is in it, and whether it opened without being set aside this
    ///     launch. Asked each time the password is set, so a fresh store after an erase is the one converted.
    ///   - backgroundTime: Keeps the app running until an unlock, a conversion or a rekey has finished.
    ///   - calibration: The key derivation's parameters for a password set here, if not calibrated on this device.
    public convenience init(
        directory: URL,
        mode: VaultStorageState.Mode,
        session: VaultStoreSession,
        settings: AppLockSettingsStore,
        erase: @escaping @MainActor () async throws -> Void,
        archives: any VaultStoreArchiving,
        deviceBackupSettings: any DeviceBackupSettingsMoving,
        purgeVaultContents: @escaping @Sendable () async -> Void,
        conversionHooks: VaultEncryptionConverter.Hooks,
        passwordHooks: VaultPasswordChangeService.Hooks,
        plainStore: @escaping @MainActor () -> (store: PersistedLocalVaultStore, openedNormally: Bool)?,
        backgroundTime: VaultBackgroundTime,
        calibration: AppLockKeyDerivationCalibration? = nil,
    ) {
        let attemptCounter = AppLockPasswordAttemptCounter()
        let unlockService = VaultUnlockService(
            directory: directory,
            session: session,
            attemptCounter: attemptCounter,
            deadlineStore: VaultStorageStateFile(directory: directory),
            purgeVaultContents: purgeVaultContents,
            backgroundTime: backgroundTime,
        )
        self.init(
            mode: mode,
            session: session,
            unlockService: unlockService,
            changeService: VaultPasswordChangeService(
                directory: directory,
                session: session,
                unlockService: unlockService,
                attemptCounter: attemptCounter,
                settings: settings,
                backgroundTime: backgroundTime,
                hooks: passwordHooks,
            ),
            attemptCounter: attemptCounter,
            settings: settings,
            erase: erase,
            stateFile: VaultStorageStateFile(directory: directory),
            archives: archives,
            makeConverter: {
                guard let (store, openedNormally) = plainStore() else { return nil }
                return VaultEncryptionConverter(
                    directory: directory,
                    plainStore: store,
                    plainStoreOpenedNormally: openedNormally,
                    session: session,
                    archives: archives,
                    attemptCounter: attemptCounter,
                    deviceBackupSettings: deviceBackupSettings,
                    hooks: conversionHooks,
                    backgroundTime: backgroundTime,
                    calibration: calibration,
                )
            },
        )
    }

    init(
        mode: VaultStorageState.Mode,
        session: VaultStoreSession,
        unlockService: VaultUnlockService,
        changeService: VaultPasswordChangeService,
        attemptCounter: AppLockPasswordAttemptCounter,
        settings: AppLockSettingsStore,
        erase: @escaping @MainActor () async throws -> Void,
        stateFile: VaultStorageStateFile,
        archives: any VaultStoreArchiving,
        makeConverter: @escaping @MainActor () -> VaultEncryptionConverter?,
    ) {
        self.mode = mode
        self.session = session
        self.unlockService = unlockService
        unlocker = AppLockPasswordUnlocker(
            unlockService: unlockService,
            attemptCounter: attemptCounter,
            settings: settings,
            erase: erase,
        )
        self.changeService = changeService
        self.attemptCounter = attemptCounter
        self.settings = settings
        self.stateFile = stateFile
        self.archives = archives
        self.makeConverter = makeConverter
    }

    public var isPasswordSet: Bool {
        mode == .password
    }

    public var erasesAfterFailedPasswords: Bool {
        settings.erasesAfterFailedPasswords
    }

    public var setAsideVaultCount: Int {
        mode == .plain ? archives.archives().count : 0
    }

    public func remainingDelay() async throws -> Duration {
        try await attemptCounter.remainingDelay()
    }

    /// Tries the password. If a turn off or on couldn't record how it ended, unlocking is refused before anything is
    /// counted: this settles it from what the vault's file holds, then tries once more.
    ///
    /// If settling finds the password was turned off, or the password was off all along and this fell behind, the vault
    /// opens with the device key: device authentication, which comes before the password, is all that takes. The lock
    /// then stops asking for the password.
    ///
    /// After an erase (`.erased`), the vault is a fresh plain store with no password.
    public func unlock(password: String) async throws -> AppLockPasswordResult {
        defer { refreshMode() }
        do {
            return try await unlocker.unlock(password: password)
        } catch VaultUnlockError.passwordChangeUnsettled {
            mode = try await changeService.settleInterruptedChange()
            guard mode == .password else { return try await openWithDeviceKey() }
            return try await unlocker.unlock(password: password)
        } catch VaultUnlockError.passwordIsOff {
            return try await openWithDeviceKey()
        }
    }

    /// Opens the vault with the device key, once device authentication has passed.
    private func openWithDeviceKey() async throws -> AppLockPasswordResult {
        try await unlockService.unlockWithDeviceKey()
        return .accepted
    }

    /// Converts the plain store into an encrypted vault, or turns the password back on after it was turned off.
    public func setPassword(_ password: String, deletingSetAsideVaults: Bool) async throws {
        defer { refreshMode() }
        switch mode {
        case .plain:
            guard let converter = makeConverter() else { throw VaultEncryptionError.plainStoreDidNotOpen }
            try await converter.encrypt(password: password, deletingArchives: deletingSetAsideVaults)
            // A new password starts with erasing off, whatever was left from before.
            settings.erasesAfterFailedPasswords = false
        case .deviceKey:
            try await changeService.turnOnPassword(password)
        case .password:
            throw VaultPasswordChangeError.passwordIsNotOff
        }
        mode = .password
    }

    public func changePassword(current: String, new: String) async throws -> AppLockPasswordResult {
        defer { refreshMode() }
        return try await Self.result(of: changeService.changePassword(current: current, new: new))
    }

    public func turnOffPassword(current: String) async throws -> AppLockPasswordResult {
        defer { refreshMode() }
        let result = try await Self.result(of: changeService.turnOffPassword(current: current))
        if result == .accepted {
            mode = .deviceKey
        }
        return result
    }

    public func makeDuressVault(current: String, password: String) async throws -> AppLockPasswordResult {
        try await Self.result(of: changeService.makeDuressVault(current: current, password: password))
    }

    public func setErasesAfterFailedPasswords(_ erases: Bool, current: String) async throws -> AppLockPasswordResult {
        try await Self.result(of: changeService.setErasesAfterFailedPasswords(erases, current: current))
    }

    /// Opens the vault with the device key, while the password is off after being on.
    public func openVaultWithoutPassword() async throws {
        guard mode == .deviceKey, await session.isLocked else { return }
        try await unlockService.unlockWithDeviceKey()
    }

    /// Locks the vault, unless it's the plain store, which the app lock only hides. An encrypted vault the session has
    /// open is always locked, even one a conversion has only just opened.
    public func lockVault() async {
        if mode == .plain, await session.unlockedStore == nil {
            return
        }
        await unlockService.lock()
    }

    /// The vault was erased (VAULT-34), leaving a fresh, empty plain store.
    public func vaultWasErased() {
        mode = .plain
    }

    /// Reads how the vault is stored from the storage state, after anything that could have changed it, so a change
    /// that threw after its rename, or a settle, can't leave `mode` behind until the app relaunches. While a turn off
    /// or on is unsettled, or an erase underway, it stays as it was: unlocking settles those.
    private func refreshMode() {
        guard let state = try? stateFile.read(), !state.isTurningThePasswordOffOrOn, state.transition != .erasing
        else { return }
        mode = state.mode
    }

    private static func result(of change: VaultPasswordChangeResult) -> AppLockPasswordResult {
        switch change {
        case .changed: .accepted
        case .wrongPassword: .wrong
        case let .mustWait(remaining): .delayed(remaining)
        case .onlyAtTheLockScreen: .onlyAtTheLockScreen
        }
    }
}
