import Foundation

/// Whether the vault's files are kept out of the device's own backups: on the Mac, Keep Out of Time Machine, in
/// Settings (VAULT-118).
///
/// It's the storage directory's own `isExcludedFromBackup`, so it covers every file in it, the vault file included,
/// however often a save replaces it, and the directory is the only record of the choice. It's off unless the user
/// turns it on, as a backup is how a lost Mac's vault comes back. It only changes backups made from then on: earlier
/// backups, and Time Machine's local snapshots of the whole disk, still hold the vault as it was.
@MainActor
@Observable
public final class VaultStorageBackupExclusion {
    /// Whether the vault's files are kept out of backups, as the directory says. Off if it can't be read.
    public private(set) var isExcluded: Bool

    private let directory: URL

    /// - Parameter directory: The vault's storage directory: on the Mac, the App Group's container.
    public init(directory: URL) {
        self.directory = directory
        isExcluded = Self.isExcluded(directory)
    }

    /// Keeps the vault's files out of backups, or lets them back in. Afterwards, `isExcluded` says what the directory
    /// has, whether or not this succeeded.
    ///
    /// - Throws: If the directory couldn't be changed.
    public func setExcluded(_ excluded: Bool) throws {
        defer { isExcluded = Self.isExcluded(directory) }
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
