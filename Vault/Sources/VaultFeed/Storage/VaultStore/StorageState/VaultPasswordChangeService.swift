import Foundation

/// Changes the open vault's App Lock Password, or turns it off and back on.
///
/// - **Change** (`changePassword(current:new:)`): checks the current password, derives the new one's key with the
///   file's salt, and rekeys the vault's slot. The rename is atomic, so either password works afterwards, never
///   neither: there's nothing to journal.
/// - **Turn off** (`turnOffPassword(current:)`): checks the current password, makes a new device key, journals
///   `turningOff`, rekeys the slot to the device key, and sets the `deviceKey` mode. The file becomes readable after
///   the first unlock, like the plain store, so the widgets can read it (VAULT-50).
/// - **Turn back on** (`turnOnPassword(_:)`), from the `deviceKey` mode: journals `turningOn`, rekeys the slot to the
///   new password (same salt), sets the `password` mode, and deletes the device key.
///
/// Every rekey gives the vault a new data key and seals its payload again (`VaultSlotFile.rekey`), and changes only
/// the open vault's slot: from a duress vault it behaves exactly the same, and never touches another. Its wrap time
/// comes from `VaultWrapStamping`, never the clock directly.
///
/// Checking the current password is an attempt like unlocking (`VaultUnlockService.checkPassword(_:opensSlot:)`):
/// counted, held to the deadline, and a password that opens another vault is simply wrong. A new password that
/// happens to open another slot is accepted without a word, as the design's "Same passwords" requires. Launch
/// recovery resolves an interrupted turn off or on by trying the device key on every slot (`VaultStorageRecovery`).
///
/// Each asks for background time (`VaultBackgroundTime`), because rekeying holds `vault-slots.lock`.
///
/// See "Turning the password off, and why it doesn't convert back" in `docs/on-device-encryption.md`.
public actor VaultPasswordChangeService {
    private let directory: URL
    private let fileSystem: any SlotFileSystem
    private let session: VaultStoreSession
    private let unlockService: VaultUnlockService
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let deviceKeyStore: any VaultDeviceKeyStoring
    private let wrapStamper: any VaultWrapStamping
    private let backgroundTime: VaultBackgroundTime
    private var isChanging = false

    /// - Parameters:
    ///   - wrapStamper: The wrap time each rekey records.
    ///   - backgroundTime: Keeps the app running until a change has finished: `.application` in the app.
    public init(
        directory: URL,
        session: VaultStoreSession,
        unlockService: VaultUnlockService,
        attemptCounter: AppLockPasswordAttemptCounter,
        deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore(),
        wrapStamper: any VaultWrapStamping,
        backgroundTime: VaultBackgroundTime,
    ) {
        self.init(
            directory: directory,
            fileSystem: LiveSlotFileSystem(),
            session: session,
            unlockService: unlockService,
            attemptCounter: attemptCounter,
            deviceKeyStore: deviceKeyStore,
            wrapStamper: wrapStamper,
            backgroundTime: backgroundTime,
        )
    }

    init(
        directory: URL,
        fileSystem: any SlotFileSystem,
        session: VaultStoreSession,
        unlockService: VaultUnlockService,
        attemptCounter: AppLockPasswordAttemptCounter,
        deviceKeyStore: any VaultDeviceKeyStoring,
        wrapStamper: any VaultWrapStamping = VaultWallClockWrapStamper(),
        backgroundTime: VaultBackgroundTime = .none,
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.session = session
        self.unlockService = unlockService
        self.attemptCounter = attemptCounter
        self.deviceKeyStore = deviceKeyStore
        self.wrapStamper = wrapStamper
        self.backgroundTime = backgroundTime
    }
}

/// How changing the password, or turning it off, turned out.
public enum VaultPasswordChangeResult: Equatable, Sendable {
    case changed
    /// The current password wasn't the open vault's. It counted as a wrong attempt, and nothing changed.
    case wrongPassword
    /// The user has to wait this long after their last wrong attempts. Nothing was tried or changed.
    case mustWait(Duration)
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
            let store = try await openVault(inMode: .password, orThrow: .passwordIsNotOn)
            if let refused = try await check(current, opens: store) {
                return refused
            }
            let key = try await passwordKey(for: new)
            try await store.rekey(
                to: key,
                protection: EncryptedVaultFile.protection(for: .password),
                wrapStamper: wrapStamper,
            )
            return .changed
        }
    }

    public func turnOffPassword(current: String) async throws -> VaultPasswordChangeResult {
        try await whileChanging {
            let store = try await openVault(inMode: .password, orThrow: .passwordIsNotOn)
            if let refused = try await check(current, opens: store) {
                return refused
            }
            let deviceKey = try deviceKeyStore.makeNewDeviceKey()
            try await rekey(store, to: .device(deviceKey), journaling: .turningOff, becoming: .deviceKey)
            return .changed
        }
    }

    /// Turns the password back on, from the `deviceKey` mode, as `password`. The current vault is open already, and
    /// device authentication opened it, so there's no current password to check.
    public func turnOnPassword(_ password: String) async throws {
        try await whileChanging {
            let store = try await openVault(inMode: .deviceKey, orThrow: .passwordIsNotOff)
            // A count left from before mustn't carry over to the new password.
            try await attemptCounter.reset()
            let key = try await passwordKey(for: password)
            try await rekey(store, to: key, journaling: .turningOn, becoming: .password)
            // Now it opens nothing. If deleting it fails, the next time the password is turned off replaces it.
            try? deviceKeyStore.removeDeviceKey()
        }
    }
}

// MARK: - Steps

extension VaultPasswordChangeService {
    private var stateFile: VaultStorageStateFile {
        VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
    }

    private func whileChanging<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        guard !isChanging else { throw VaultPasswordChangeError.changeUnderway }
        isChanging = true
        defer { isChanging = false }
        return try await backgroundTime.whileRunning(body)
    }

    /// The open vault's store, if the vault is stored in `mode` with nothing underway.
    private func openVault(
        inMode mode: VaultStorageState.Mode,
        orThrow error: VaultPasswordChangeError,
    ) async throws -> EncryptedVaultStore {
        let state = try stateFile.read()
        guard state.mode == mode, state.transition == nil else { throw error }
        guard let store = await session.unlockedStore else { throw VaultPasswordChangeError.noOpenVault }
        return store
    }

    /// Checks the password against the open vault's slot, as an attempt. `nil` if it's right.
    private func check(
        _ password: String,
        opens store: EncryptedVaultStore,
    ) async throws -> VaultPasswordChangeResult? {
        switch try await unlockService.checkPassword(password, opensSlot: store.slotIndex) {
        case .right: nil
        case .wrong: .wrongPassword
        case let .mustWait(remaining): .mustWait(remaining)
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

    /// Journals the change of mode, rekeys the vault's slot to `rootKey`, then sets the new mode.
    ///
    /// If rekeying fails, the file is as it was, so the journal is cleared again. If that fails too, or the app
    /// stops at any point, launch recovery settles the mode by trying the device key on every slot. And if setting the
    /// new mode fails after the rekey, recovery settles it the same way.
    ///
    /// Each write updates the state as it is then, so an unlock deadline raised meanwhile is kept.
    private func rekey(
        _ store: EncryptedVaultStore,
        to rootKey: VaultSlotRootKey,
        journaling transition: VaultStorageState.Transition,
        becoming mode: VaultStorageState.Mode,
    ) async throws {
        try await stateFile.update { $0.transition = transition }
        do {
            try await store.rekey(
                to: rootKey,
                protection: EncryptedVaultFile.protection(for: mode),
                wrapStamper: wrapStamper,
            )
        } catch {
            _ = try? await stateFile.update { state in
                if state.transition == transition {
                    state.transition = nil
                }
            }
            throw error
        }
        _ = try? await stateFile.update { state in
            state.mode = mode
            state.transition = nil
        }
    }

    private static func normalized(_ password: String) -> String {
        password.precomposedStringWithCanonicalMapping
    }
}
