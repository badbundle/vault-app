import Foundation

/// The App Lock Password as the encrypted vault implements it, for unlocking: VAULT-46's `VaultUnlockService`, with
/// the device's attempt counter and unlock deadline.
///
/// This is what the AutoFill extension unlocks with, in its own process. It counts attempts with the same keychain
/// counter as the app, so a guess in AutoFill waits, and counts toward an erase, just as one on the lock screen does.
/// Setting, changing and turning off the password are only for the app's Settings (VAULT-47 and VAULT-48), so here
/// they throw.
@MainActor
public final class EncryptedVaultPasswordService: AppLockPasswordService {
    public let isPasswordSet: Bool
    private let unlockService: VaultUnlockService
    private let attemptCounter: AppLockPasswordAttemptCounter

    /// - Parameters:
    ///   - directory: The vault's storage directory, with the encrypted file and the storage state in it.
    ///   - session: The store session this process reads and writes the vault through.
    ///   - purgeVaultContents: Forgets everything this process read from the vault. Called every time it locks.
    public convenience init(
        directory: URL,
        session: VaultStoreSession,
        purgeVaultContents: @escaping @Sendable () async -> Void,
    ) {
        let stateFile = VaultStorageStateFile(directory: directory)
        let attemptCounter = AppLockPasswordAttemptCounter()
        self.init(
            unlockService: VaultUnlockService(
                directory: directory,
                session: session,
                attemptCounter: attemptCounter,
                deadlineStore: stateFile,
                purgeVaultContents: purgeVaultContents,
            ),
            attemptCounter: attemptCounter,
            isPasswordSet: (try? stateFile.read().mode) == .password,
        )
    }

    init(unlockService: VaultUnlockService, attemptCounter: AppLockPasswordAttemptCounter, isPasswordSet: Bool) {
        self.unlockService = unlockService
        self.attemptCounter = attemptCounter
        self.isPasswordSet = isPasswordSet
    }

    public func remainingDelay() async throws -> Duration {
        try await attemptCounter.remainingDelay()
    }

    public func unlock(password: String) async throws -> AppLockPasswordResult {
        switch try await unlockService.unlock(password: password) {
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

    /// Whether this process has the memory to derive the key and open the vault. The AutoFill extension asks before
    /// it offers the password, and sends the user to the app instead if not.
    public func hasMemoryHeadroomToUnlock() async throws -> Bool {
        try await unlockService.hasMemoryHeadroomToUnlock()
    }

    /// Locks the vault again, if it's open: its keys and everything read from it go.
    public func lockVault() async {
        await unlockService.lock()
    }
}
