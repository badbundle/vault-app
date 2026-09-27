import Foundation

/// How the vault is stored on this device, whether a change between the two ways is underway, and the device's
/// unlock deadline.
///
/// It's kept in `vault-storage-state.json` (`VaultStorageStateFile`). There's no file until encryption is first
/// turned on, so a device that has never had an App Lock Password has none. It isn't secret: the lock screen already
/// shows whether a password is set. See "Storage modes" in `docs/on-device-encryption.md`.
public struct VaultStorageState: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// Today's SQLite store (`PersistedLocalVaultStore`).
        case plain
        /// The encrypted vault file, whose vaults the App Lock Password opens.
        case password
        /// The encrypted vault file, with the open vault's key wrapped by the device key rather than a password: the
        /// password has been turned off. Device authentication alone opens it (`VaultDeviceKeyStoring`).
        case deviceKey
    }

    /// A change of mode that's underway: the journal that lets launch recovery finish or undo it.
    public enum Transition: Codable, Equatable, Sendable {
        /// Converting the plain store into an encrypted vault (`VaultEncryptionConverter`). The plain store is still
        /// the vault: recovery deletes the encrypted file, if there is one.
        case encrypting
        /// The conversion has committed. Recovery finishes deleting the plain store's files, its pending rehash
        /// files, and these archives of it (folder names), whose deletion the user confirmed.
        case deletingPlainStore(archives: [String])
        /// The plain store is gone, or the password has just been turned back on. The QuickType identity store still
        /// has to be cleared and the widgets reloaded, which the app does at its next launch if it was stopped first
        /// (`VaultStorageRecovery.finishClearingSystemSurfaces(_:)`).
        case clearingSystemSurfaces
        /// The password has just been turned off. The QuickType identity store still has to be filled again from the
        /// vault and the widgets reloaded, which the app does at its next launch if it was stopped first
        /// (`VaultStorageRecovery.finishSyncingSystemSurfaces(_:)`).
        case syncingSystemSurfaces
        /// Erasing every vault, back to a fresh plain store (`VaultEraser`), whatever the mode says. Nothing may open
        /// a store until the erase has finished: the app finishes it at launch.
        case erasing
        /// Turning the password off: the open vault's slot is being rekeyed to the device key. Recovery tries the
        /// device key on every slot: if one opens, the rekey happened.
        case turningOff
        /// Turning the password back on: the vault's slot is being rekeyed to a new password. Recovery tries the
        /// device key on every slot: if none opens, the rekey happened.
        case turningOn
    }

    public var mode: Mode
    public var transition: Transition?
    /// How long every unlock attempt takes on this device, whatever its outcome (`VaultUnlockService`). Set by
    /// calibration when the encrypted vault is created, and only ever raised.
    public var unlockDeadline: Duration?

    public init(mode: Mode, transition: Transition? = nil, unlockDeadline: Duration? = nil) {
        self.mode = mode
        self.transition = transition
        self.unlockDeadline = unlockDeadline
    }

    /// A device that has never turned encryption on, or has undone a conversion.
    public static let plain = VaultStorageState(mode: .plain)

    /// Whether the plain store is the vault, with nothing underway that would change that. Only then may anything
    /// open it.
    public var isPlain: Bool {
        mode == .plain && transition == nil
    }

    /// Whether the journal shows the password being turned off or back on.
    var isTurningThePasswordOffOrOn: Bool {
        transition == .turningOff || transition == .turningOn
    }

    /// Whether the mode is settled, with at most the system surfaces still to catch up with it: they don't change
    /// what opens the vault.
    var isSettled: Bool {
        switch transition {
        case nil, .clearingSystemSurfaces?, .syncingSystemSurfaces?: true
        case .encrypting?, .deletingPlainStore?, .erasing?, .turningOff?, .turningOn?: false
        }
    }
}

/// `vault-storage-state.json`, in the vault's storage directory.
///
/// It's replaced atomically: written to a temp file, flushed with `F_FULLFSYNC`, renamed over the old one, and the
/// directory flushed. Going back to plain removes it.
///
/// The rename is the commit point, as for the encrypted file: once it's done the new state holds, so a failure to
/// flush the directory afterwards doesn't count as a failure to write it.
struct VaultStorageStateFile: Sendable {
    static let fileName = "vault-storage-state.json"
    static let temporaryFilePrefix = ".vault-storage-state.tmp-"

    let directory: URL
    let fileSystem: any SlotFileSystem

    init(directory: URL, fileSystem: any SlotFileSystem = LiveSlotFileSystem()) {
        self.directory = directory
        self.fileSystem = fileSystem
    }

    var url: URL {
        directory.appending(path: Self.fileName)
    }

    /// The state, or `.plain` if there's no file.
    func read() throws -> VaultStorageState {
        guard let data = try fileSystem.contents(of: url) else { return .plain }
        return try JSONDecoder().decode(VaultStorageState.self, from: data)
    }

    /// Replaces the state, or removes the file for `.plain`.
    func write(_ state: VaultStorageState) throws {
        guard state != .plain else {
            try fileSystem.removeItem(at: url)
            try? fileSystem.synchronizeDirectory(at: directory)
            return
        }
        let temporaryURL = directory.appending(path: Self.temporaryFilePrefix + UUID().uuidString)
        do {
            // Readable once the device has been unlocked after starting up, like the plain store, so the widgets
            // can tell the vault is encrypted even while the device is locked.
            try fileSystem.createFile(
                at: temporaryURL,
                contents: JSONEncoder().encode(state),
                protection: .completeUntilFirstUserAuthentication,
            )
            try fileSystem.synchronizeFile(at: temporaryURL)
            try fileSystem.moveItem(at: temporaryURL, replacing: url)
        } catch {
            try? fileSystem.removeItem(at: temporaryURL)
            throw error
        }
        try? fileSystem.synchronizeDirectory(at: directory)
    }

    /// Reads the state, changes it, and writes it back if it changed, with no other `update(_:)` in between, in this
    /// process or another. Anything that changes one part of the state while something else might change another
    /// goes through this, so neither undoes the other: the app ending a transition or changing the mode, and an
    /// unlock attempt raising the deadline, in the app or in the AutoFill extension.
    ///
    /// It holds `vault-slots.lock` meanwhile, as writers of the encrypted file do, so no rekey changes the file
    /// while `change` looks at it either. Don't call it holding the lock.
    ///
    /// - Returns: The state as it is now, and what `change` returned.
    @discardableResult
    func update<Result>(
        _ change: (inout VaultStorageState) throws -> Result,
    ) async throws -> (state: VaultStorageState, result: Result) {
        try await lockFile.withLock { _ in
            try applying(change)
        }
    }

    /// As `update(_:)`, but waits for the lock blocking the thread: for launch recovery, which runs synchronously.
    @discardableResult
    func updateBlockingTheThread<Result>(
        _ change: (inout VaultStorageState) throws -> Result,
    ) throws -> (state: VaultStorageState, result: Result) {
        try lockFile.withLockBlockingTheThread { _ in
            try applying(change)
        }
    }

    private var lockFile: EncryptedVaultFile {
        EncryptedVaultFile(directory: directory, fileSystem: fileSystem)
    }

    private func applying<Result>(
        _ change: (inout VaultStorageState) throws -> Result,
    ) throws -> (state: VaultStorageState, result: Result) {
        var state = try read()
        let old = state
        let result = try change(&state)
        if state != old {
            try write(state)
        }
        return (state, result)
    }

    /// Removes temp files a crash left behind while writing the state.
    func removeStrayTemporaryFiles() throws {
        for url in try fileSystem.contentsOfDirectory(at: directory)
            where url.lastPathComponent.hasPrefix(Self.temporaryFilePrefix)
        {
            try fileSystem.removeItem(at: url)
        }
    }
}

// MARK: - Unlock deadline

extension VaultStorageStateFile: VaultUnlockDeadlineStoring {
    struct NoUnlockDeadline: Error {}

    func unlockDeadline() async throws -> Duration {
        guard let deadline = try read().unlockDeadline else { throw NoUnlockDeadline() }
        return deadline
    }

    func raiseUnlockDeadline(to deadline: Duration) async throws {
        try await update { state in
            guard let current = state.unlockDeadline, deadline > current else { return }
            state.unlockDeadline = deadline
        }
    }

    func isErasing() async throws -> Bool {
        try read().transition == .erasing
    }
}

// MARK: - Extensions

extension VaultStorageState {
    /// Whether the plain store is the vault, for a process that mustn't recover from an interrupted change: the
    /// AutoFill and widget extensions. Anything else, including a state file that can't be read, counts as no, so
    /// they never open a plain store that's being converted or is out of date.
    public static func isPlain(inDirectory directory: URL) -> Bool {
        current(inDirectory: directory)?.isPlain ?? false
    }

    /// The state as it is now, for a process that mustn't recover from an interrupted change: the AutoFill and widget
    /// extensions. `nil` if it can't be read.
    public static func current(inDirectory directory: URL) -> VaultStorageState? {
        try? VaultStorageStateFile(directory: directory).read()
    }
}
