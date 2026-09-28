import Foundation

/// What an app extension checks on every call to an encrypted vault it opened: that the vault is still stored the way
/// it was when it opened it. `GuardedPlainVaultStore` does the same for the plain store.
///
/// The app can turn the App Lock Password on or off, or erase the vault, while an extension's process lives on with
/// the vault open, as an AutoFill sheet left open in another app can. Once the storage state says anything else, reads
/// find nothing and writes throw `VaultStoreSessionError.locked`, as for a locked session. A save checks again holding
/// the file's lock, which a rekey and an erase take, so none lands after either. The app has no guard: it makes those
/// changes itself.
struct VaultAccessGuard: Sendable {
    /// How the vault could be opened when it was.
    let openedIn: VaultAccessMode
    /// How the vault can be opened now, from the storage state.
    let currentMode: @Sendable () -> VaultAccessMode
    /// Whether the vault was opened to change it, as well as to show it. A widget only shows it.
    let allowsWrites: Bool

    /// Whether the vault is still stored the way it was when it opened.
    var isStillOpen: Bool {
        currentMode() == openedIn
    }

    /// - Throws: `VaultStoreSessionError.locked` if writes aren't allowed, or the vault isn't stored as it was any
    ///   more.
    func checkWrite() throws {
        guard allowsWrites, isStillOpen else { throw VaultStoreSessionError.locked }
    }
}

extension VaultAccessMode {
    /// How the vault in `directory` can be opened now, from its storage state file, read without its lock.
    static func reader(
        directory: URL,
        fileSystem: any SlotFileSystem = LiveSlotFileSystem(),
    ) -> @Sendable () -> VaultAccessMode {
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        return { VaultAccessMode(state: (try? stateFile.readWithoutRecovering()) ?? nil) }
    }
}
