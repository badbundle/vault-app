import Foundation

/// Changes the open vault's App Lock Password, or turns it off and back on, and makes duress vaults from it.
///
/// - **Change** (`changePassword(current:new:)`): checks the current password, derives the new one's key with the
///   file's salt, and rekeys the vault's slot. The rename is atomic, so either password works afterwards, never
///   neither: there's nothing to journal.
/// - **Turn off** (`turnOffPassword(current:)`): checks the current password, makes a new device key, journals
///   `turningOff`, rekeys the slot to the device key, and settles the `deviceKey` mode. The file becomes readable
///   after the first unlock, like the plain store, so the widgets can read it (VAULT-50).
/// - **Turn back on** (`turnOnPassword(_:)`), from the `deviceKey` mode: journals `turningOn`, rekeys the slot to the
///   new password (same salt), settles the `password` mode, and deletes the device key.
/// - **Erasing after failed passwords** (`setErasesAfterFailedPasswords(_:current:)`, VAULT-34): checks the current
///   password, and turns it on or off. It's a setting of the device, not of a vault, so the open vault's own password
///   changes it, a duress vault's included. Turning the password off, or back on, turns it off.
/// - **Make a duress vault** (`makeDuressVault(current:password:)`, VAULT-23): checks the current password, refuses
///   a new one equal to it, and makes the duress vault (`EncryptedVaultStore.makeDuressVault(password:)`).
///
/// No check tries the attempt that would make the erase threshold's wrong password in a row
/// (`.onlyAtTheLockScreen`): that one is only ever tried at the lock screen.
///
/// Every rekey gives the vault a new data key and seals its payload again (`VaultSlotFile.rekey`), and changes only
/// the open vault's slot: from a duress vault it behaves exactly the same, and never touches another. Its wrap time
/// is stamped by the store's `VaultWrapStamping`, never read from the clock directly. It runs as a call underway on
/// the store session, so locking waits for it, and nothing starts once the vault has locked.
///
/// Checking the current password is an attempt like unlocking (`VaultUnlockService.checkPassword(_:opensSlot:)`):
/// counted, held to the deadline, and a password that opens another vault is simply wrong. A new password that
/// happens to open another slot is accepted without a word, as the design's "Same passwords" requires.
///
/// A turn off or on settles its mode by trying the device key on every slot, as launch recovery does
/// (`VaultStorageRecovery`), so what's recorded is what the file holds. If that can't be saved, the journal stays:
/// unlocking with a password is refused without counting until it's settled, which the next change, the app's
/// password service or the next launch does.
///
/// Each asks for background time (`VaultBackgroundTime`), because rekeying holds `vault-slots.lock`.
///
/// **System surfaces.** Once a turn off or on has settled, the widgets, QuickType and AutoFill catch up with the new
/// mode through `Hooks`: turning it off fills QuickType again from the vault, turning it on empties it, and both
/// reload the widgets. Settling journals the step, so if the app stops first, or the hook fails, the next launch runs
/// it again (`VaultStorageRecovery.finishSyncingSystemSurfaces(_:)`, `finishClearingSystemSurfaces(_:)`).
///
/// See "Turning the password off, and why it doesn't convert back" in `docs/on-device-encryption.md`.
public actor VaultPasswordChangeService {
    /// What the app does outside storage once the password is off or on.
    public struct Hooks: Sendable {
        /// Fills the QuickType identity store from the vault, now the password is off, and reloads the widgets.
        public var passwordDidTurnOff: @Sendable () async throws -> Void
        /// Empties the QuickType identity store, now the password is on, and reloads the widgets.
        public var passwordDidTurnOn: @Sendable () async throws -> Void

        public init(
            passwordDidTurnOff: @escaping @Sendable () async throws -> Void,
            passwordDidTurnOn: @escaping @Sendable () async throws -> Void,
        ) {
            self.passwordDidTurnOff = passwordDidTurnOff
            self.passwordDidTurnOn = passwordDidTurnOn
        }
    }

    private let directory: URL
    private let fileSystem: any SlotFileSystem
    private let session: VaultStoreSession
    private let unlockService: VaultUnlockService
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let deviceKeyStore: any VaultDeviceKeyStoring
    private let settings: AppLockSettingsStore
    private let backgroundTime: VaultBackgroundTime
    private let hooks: Hooks
    private var isChanging = false

    /// - Parameters:
    ///   - settings: The app lock's settings, with erasing after failed passwords.
    ///   - backgroundTime: Keeps the app running until a change has finished: `.application` in the app.
    ///   - hooks: Brings the widgets, QuickType and AutoFill up to date with the password turned off or on.
    public init(
        directory: URL,
        session: VaultStoreSession,
        unlockService: VaultUnlockService,
        attemptCounter: AppLockPasswordAttemptCounter,
        deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore(),
        settings: AppLockSettingsStore,
        backgroundTime: VaultBackgroundTime,
        hooks: Hooks,
    ) {
        self.init(
            directory: directory,
            fileSystem: LiveSlotFileSystem(),
            session: session,
            unlockService: unlockService,
            attemptCounter: attemptCounter,
            deviceKeyStore: deviceKeyStore,
            settings: settings,
            backgroundTime: backgroundTime,
            hooks: hooks,
        )
    }

    init(
        directory: URL,
        fileSystem: any SlotFileSystem,
        session: VaultStoreSession,
        unlockService: VaultUnlockService,
        attemptCounter: AppLockPasswordAttemptCounter,
        deviceKeyStore: any VaultDeviceKeyStoring,
        settings: AppLockSettingsStore,
        backgroundTime: VaultBackgroundTime = .none,
        hooks: Hooks = Hooks(passwordDidTurnOff: {}, passwordDidTurnOn: {}),
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.session = session
        self.unlockService = unlockService
        self.attemptCounter = attemptCounter
        self.deviceKeyStore = deviceKeyStore
        self.settings = settings
        self.backgroundTime = backgroundTime
        self.hooks = hooks
    }
}

/// How changing the password, or turning it off, turned out.
public enum VaultPasswordChangeResult: Equatable, Sendable {
    /// Done: the password is changed, off or back on, erasing after failed passwords is on or off, or the duress vault
    /// is made.
    case changed
    /// The current password wasn't the open vault's. It counted as a wrong attempt, and nothing changed.
    ///
    /// - reachesEraseThreshold: As for unlocking (`VaultUnlockResult.wrongPassword(reachesEraseThreshold:)`): a
    ///   wrong current password counts towards the erase after too many, if the user has turned it on. Never show it.
    case wrongPassword(reachesEraseThreshold: Bool)
    /// The user has to wait this long after their last wrong attempts. Nothing was tried or changed.
    case mustWait(Duration)
    /// The check would have been the erase threshold's attempt in a row, which is only ever tried at the lock screen,
    /// erasing on or off. Nothing was tried, counted or changed.
    case onlyAtTheLockScreen
}

public enum VaultPasswordChangeError: Error, Equatable, Sendable {
    /// The new password is the same as the current one.
    case newPasswordMatchesCurrent
    /// The password isn't on, so it can't be changed or turned off.
    case passwordIsNotOn
    /// The password isn't off after being on, so it can't be turned back on.
    case passwordIsNotOff
    /// No encrypted vault is open.
    case noOpenVault
    /// Another change is still underway.
    case changeUnderway
}

// MARK: - Operations

extension VaultPasswordChangeService {
    public func changePassword(current: String, new: String) async throws -> VaultPasswordChangeResult {
        try await whileChanging {
            guard Self.normalized(current) != Self.normalized(new) else {
                throw VaultPasswordChangeError.newPasswordMatchesCurrent
            }
            let vault = try await openVault(inMode: .password, orThrow: .passwordIsNotOn)
            if let refused = try await check(current, opens: vault.store) {
                return refused
            }
            let key = try await passwordKey(for: new)
            try await session.whileUnlocked(vault.store, since: vault.lockEpoch) {
                try await vault.store.rekey(to: key, protection: EncryptedVaultFile.protection(for: .password))
            }
            return .changed
        }
    }

    public func turnOffPassword(current: String) async throws -> VaultPasswordChangeResult {
        try await whileChanging {
            let vault = try await openVault(inMode: .password, orThrow: .passwordIsNotOn)
            if let refused = try await check(current, opens: vault.store) {
                return refused
            }
            let deviceKeyStore = deviceKeyStore
            try await rekey(vault, journaling: .turningOff, becoming: .deviceKey) {
                try .device(deviceKeyStore.makeNewDeviceKey())
            }
            // Erasing after failed passwords means nothing without one.
            settings.erasesAfterFailedPasswords = false
            return .changed
        }
    }

    /// Turns the password back on, from the `deviceKey` mode, as `password`. The current vault is open already, and
    /// device authentication opened it, so there's no current password to check.
    ///
    /// It clears the count of attempts in a row on device authentication alone. That's accepted (MANIFESTO C4): with
    /// the password off, device authentication opens the vault anyway, so the count guards nothing a coercer couldn't
    /// already open, and a count left from before mustn't carry over to the new password. The recent count, which the
    /// delays follow, stays, so turning the password off and on again doesn't shorten them.
    public func turnOnPassword(_ password: String) async throws {
        try await whileChanging {
            let vault = try await openVault(inMode: .deviceKey, orThrow: .passwordIsNotOff)
            try await attemptCounter.resetCountInARow()
            let key = try await passwordKey(for: password)
            // Settling deletes the device key, once it's shown to open nothing.
            try await rekey(vault, journaling: .turningOn, becoming: .password) { key }
            // A password turned back on starts with erasing off, as a new one does.
            settings.erasesAfterFailedPasswords = false
        }
    }

    /// Turns erasing after failed passwords on or off (VAULT-34), once `current` is shown to be the open vault's
    /// password: the same counted check, held to the deadline, as changing the password. It's a setting of the device,
    /// so it works the same from every vault, and a duress vault's own password turns it on or off for every vault
    /// (MANIFESTO.md C2). See "Consequences to accept" in `docs/on-device-encryption.md`.
    ///
    /// A wrong password counts toward an erase like any other, but this never erases: the vault is open. Only the
    /// lock screen erases (`AppLockPasswordUnlocker`).
    public func setErasesAfterFailedPasswords(
        _ erases: Bool,
        current: String,
    ) async throws -> VaultPasswordChangeResult {
        try await whileChanging {
            let vault = try await openVault(inMode: .password, orThrow: .passwordIsNotOn)
            if let refused = try await check(current, opens: vault.store) {
                return refused
            }
            settings.erasesAfterFailedPasswords = erases
            return .changed
        }
    }

    /// Makes a duress vault from the open vault, for `password`, once `current` is shown to be the open vault's own
    /// password: the same counted check, held to the deadline, as changing the password, and never the attempt that
    /// would make the erase threshold's in a row.
    ///
    /// Once the check has passed, a new password equal to `current`, once both are in Unicode's composed form, is
    /// refused (`VaultDuressVaultError.matchesAppLockPassword`). It's the only one refused, and the refusal is the same
    /// in every vault. One that happens to open another vault is accepted without a word, as the design's "Same
    /// passwords" requires: nothing is tried against any other slot.
    ///
    /// - Throws: `VaultDuressVaultError` if it's refused or can't be made, or what making it threw. The file is
    ///   unchanged then.
    public func makeDuressVault(current: String, password: String) async throws -> VaultPasswordChangeResult {
        try await whileChanging {
            let vault = try await openVault(inMode: .password, orThrow: .passwordIsNotOn)
            if let refused = try await check(current, opens: vault.store) {
                return refused
            }
            guard Self.normalized(current) != Self.normalized(password) else {
                throw VaultDuressVaultError.matchesAppLockPassword
            }
            try await session.whileUnlocked(vault.store, since: vault.lockEpoch) {
                try await vault.store.makeDuressVault(password: password)
            }
            return .changed
        }
    }

    /// Settles a turn off or on that couldn't record how it ended, from what the device key opens, as launch
    /// recovery does. The app's password service calls it when unlocking with a password is refused because one is
    /// pending (`VaultUnlockError.passwordChangeUnsettled`), then tries again. The change operations settle one
    /// themselves before they start.
    ///
    /// - Returns: How the vault is stored now.
    /// - Throws: `VaultStorageRecovery.Failure.fileUnreadableWhileLocked` if the device is locked, or
    ///   `VaultPasswordChangeError.changeUnderway`.
    public func settleInterruptedChange() async throws -> VaultStorageState.Mode {
        try await whileChanging {
            let mode = try await recovery.settleTurningThePasswordOffOrOn()
            await catchUpSystemSurfaces()
            return mode
        }
    }
}

// MARK: - Steps

extension VaultPasswordChangeService {
    /// How many times settling a turn off or on is tried, before it's left for the unlock path or the next launch.
    static let settleAttempts = 3

    /// The vault the session has open, and the `lockEpoch` it was open in.
    private struct OpenVault {
        var store: EncryptedVaultStore
        var lockEpoch: Int
    }

    private var stateFile: VaultStorageStateFile {
        VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
    }

    private var recovery: VaultStorageRecovery {
        VaultStorageRecovery(directory: directory, fileSystem: fileSystem, deviceKeyStore: deviceKeyStore)
    }

    private func whileChanging<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        guard !isChanging else { throw VaultPasswordChangeError.changeUnderway }
        isChanging = true
        defer { isChanging = false }
        return try await backgroundTime.whileRunning(body)
    }

    /// The open vault, if the vault is stored in `mode`. A turn off or on that couldn't record how it ended is settled
    /// first, and the system surfaces caught up with it.
    private func openVault(
        inMode mode: VaultStorageState.Mode,
        orThrow error: VaultPasswordChangeError,
    ) async throws -> OpenVault {
        var state = try stateFile.read()
        if state.isTurningThePasswordOffOrOn {
            _ = try await recovery.settleTurningThePasswordOffOrOn()
            await catchUpSystemSurfaces()
            state = try stateFile.read()
        }
        guard state.mode == mode, state.isSettled else { throw error }
        guard let (store, lockEpoch) = await session.unlockedStore else {
            throw VaultPasswordChangeError.noOpenVault
        }
        return OpenVault(store: store, lockEpoch: lockEpoch)
    }

    /// Checks the password against the open vault's slot, as an attempt. `nil` if it's right.
    private func check(
        _ password: String,
        opens store: EncryptedVaultStore,
    ) async throws -> VaultPasswordChangeResult? {
        switch try await unlockService.checkPassword(password, opensSlot: store.slotIndex) {
        case .right: nil
        case let .wrong(reachesEraseThreshold): .wrongPassword(reachesEraseThreshold: reachesEraseThreshold)
        case let .mustWait(remaining): .mustWait(remaining)
        case .stoppedBeforeEraseThreshold: .onlyAtTheLockScreen
        }
    }

    /// The password's key with this file's Argon2id parameters and salt, derived off the actor.
    private func passwordKey(for password: String) async throws -> VaultSlotRootKey {
        guard let (header, _) = try EncryptedVaultFile(directory: directory, fileSystem: fileSystem).readHeader() else {
            throw EncryptedVaultStoreError.fileMissing
        }
        return try await Task.detached(priority: .userInitiated) {
            try header.passwordKey(for: password)
        }.value
    }

    /// Journals the change of mode, rekeys the vault's slot to the key `rootKey` makes, then settles the mode from
    /// what the file holds, as launch recovery would if the app stopped now, rather than from what the rekey
    /// reported. So a rekey that failed leaves the mode as it was, and one that worked moves it on.
    ///
    /// All of it runs as a call underway on the session, so a lock waits for it, and nothing starts if the vault has
    /// locked since it was opened. If settling can't save the state, it's tried again, and after that the journal is
    /// left for the unlock path, which refuses a password without counting it until it's settled, or the next launch.
    private func rekey(
        _ vault: OpenVault,
        journaling transition: VaultStorageState.Transition,
        becoming mode: VaultStorageState.Mode,
        to rootKey: @escaping @Sendable () throws -> VaultSlotRootKey,
    ) async throws {
        let stateFile = stateFile
        let recovery = recovery
        do {
            try await session.whileUnlocked(vault.store, since: vault.lockEpoch) {
                let key = try rootKey()
                try await stateFile.update { $0.transition = transition }
                var rekeyError: (any Error)?
                do {
                    try await vault.store.rekey(to: key, protection: EncryptedVaultFile.protection(for: mode))
                } catch {
                    rekeyError = error
                }
                var attempts = 0
                while attempts < Self.settleAttempts, (try? await recovery.settleTurningThePasswordOffOrOn()) == nil {
                    attempts += 1
                }
                if let rekeyError {
                    throw rekeyError
                }
            }
        } catch {
            // Settling journals the surfaces for whichever mode it landed in, even when the rekey failed.
            await catchUpSystemSurfaces()
            throw error
        }
        await catchUpSystemSurfaces()
    }

    /// Brings the widgets, QuickType and AutoFill up to date with the mode settling landed in. If a hook fails, the
    /// journal keeps the step for the next launch.
    private func catchUpSystemSurfaces() async {
        let recovery = recovery
        try? await recovery.finishSyncingSystemSurfaces(hooks.passwordDidTurnOff)
        try? await recovery.finishClearingSystemSurfaces(hooks.passwordDidTurnOn)
    }

    private static func normalized(_ password: String) -> String {
        password.precomposedStringWithCanonicalMapping
    }
}
