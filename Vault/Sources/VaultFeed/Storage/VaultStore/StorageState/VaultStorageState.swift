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
    }

    /// A change of mode that's underway: the journal that lets launch recovery finish or undo it.
    public enum Transition: Codable, Equatable, Sendable {
        /// Converting the plain store into an encrypted vault (`VaultEncryptionConverter`). The plain store is still
        /// the vault: recovery deletes the encrypted file, if there is one.
        case encrypting
        /// The conversion has committed. Recovery finishes deleting the plain store's files, its pending rehash
        /// files, and these archives of it (folder names), whose deletion the user confirmed.
        case deletingPlainStore(archives: [String])
        /// The plain store is gone. The QuickType identity store still has to be cleared and the widgets reloaded,
        /// which the app does at its next launch if it was stopped first
        /// (`VaultStorageRecovery.finishClearingSystemSurfaces(_:)`).
        case clearingSystemSurfaces
        /// Erasing every vault, back to a fresh plain store (`VaultEraser`), whatever the mode says. Nothing may open
        /// a store until the erase has finished: the app finishes it at launch.
        case erasing
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
        var state = try read()
        guard let current = state.unlockDeadline, deadline > current else { return }
        state.unlockDeadline = deadline
        try write(state)
    }
}

// MARK: - Extensions

extension VaultStorageState {
    /// Whether the plain store is the vault, for a process that mustn't recover from an interrupted change: the
    /// AutoFill and widget extensions. Anything else, including a state file that can't be read, counts as no, so
    /// they never open a plain store that's being converted or is out of date.
    public static func isPlain(inDirectory directory: URL) -> Bool {
        (try? VaultStorageStateFile(directory: directory).read().isPlain) ?? false
    }
}
