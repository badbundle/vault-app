import Foundation

/// Keeps the vault's files out of the device's own backups, unless the user turns that off: on the Mac, Keep Out of
/// Time Machine, in Settings (VAULT-118).
///
/// It's on by default, for new and existing vaults alike, as keeping the vault out of backups is the protective choice
/// (MANIFESTO C7): a backup holds the vault as it was, with the App Lock Password it had then, and items deleted since.
/// A lost Mac's vault comes back from a backup made in Vault instead. Turning it off is kept with the other device
/// settings that protect the vault, where only Vault can change it (`AppLockSettingsStore`), and if that can't be
/// read, the vault is kept out.
///
/// It's the storage directory's own `isExcludedFromBackup`, so it covers every file in it, the vault file included,
/// however often a save replaces it. `apply()` sets it at every launch, from what the user chose. It only changes
/// backups made from then on: earlier backups, and Time Machine's local snapshots of the whole disk, still hold the
/// vault as it was.
@MainActor
@Observable
public final class VaultStorageBackupExclusion {
    /// Whether the vault's files are kept out of backups, as the directory says now. Off if it can't be read.
    public private(set) var isExcluded: Bool

    private let directory: URL
    private let settings: AppLockSettingsStore

    /// - Parameters:
    ///   - directory: The vault's storage directory: on the Mac, the App Group's container.
    ///   - settings: Where turning it off is kept.
    public init(directory: URL, settings: AppLockSettingsStore) {
        self.directory = directory
        self.settings = settings
        isExcluded = Self.isExcluded(directory)
    }

    /// Keeps the vault's files out of backups, unless the user has turned that off, or lets them in if they have. Call
    /// it at launch, so a vault from before the setting, or a directory whose exclusion was cleared, is kept out too.
    /// If the directory can't be changed, it's tried again at the next launch.
    public func apply() {
        let excluded = !((try? settings.loadIncludesVaultInBackups()) ?? false)
        try? setDirectoryExcluded(excluded)
    }

    /// Keeps the vault's files out of backups, or lets them in, and remembers the choice. The choice is stored first,
    /// so if the directory then can't be changed, the next launch changes it. Afterwards, `isExcluded` says what the
    /// directory has.
    ///
    /// - Throws: If the choice couldn't be stored, and nothing changed, or the directory couldn't be changed.
    public func setExcluded(_ excluded: Bool) throws {
        try settings.setIncludesVaultInBackups(!excluded)
        try setDirectoryExcluded(excluded)
    }

    private func setDirectoryExcluded(_ excluded: Bool) throws {
        defer { isExcluded = Self.isExcluded(directory) }
        guard Self.isExcluded(directory) != excluded else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        var url = directory
        try url.setResourceValues(values)
    }

    /// Whether `directory` is kept out of backups, read afresh rather than from what the URL last read.
    private static func isExcluded(_ directory: URL) -> Bool {
        var url = directory
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }
}
