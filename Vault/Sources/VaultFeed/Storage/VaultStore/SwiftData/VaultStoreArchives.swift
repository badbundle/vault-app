import Foundation

/// A vault set aside because it couldn't be opened.
public struct VaultStoreArchive: Equatable, Sendable {
    public var url: URL
    /// When it was set aside.
    public var date: Date

    public init(url: URL, date: Date) {
        self.url = url
        self.date = date
    }
}

/// The vaults set aside because they couldn't be opened.
///
/// @mockable
public protocol VaultStoreArchiving: Sendable {
    /// The vaults set aside, oldest first.
    func archives() -> [VaultStoreArchive]
    /// Deletes every vault set aside.
    func deleteAll() throws
}

/// No vaults set aside, for a store that never sets one aside, such as one in memory.
public struct NoVaultStoreArchives: VaultStoreArchiving {
    public init() {}

    public func archives() -> [VaultStoreArchive] {
        []
    }

    public func deleteAll() {}
}

/// The folders `PersistedLocalVaultStoreFactory` moves the store into when it can't open it.
///
/// When the store fails to open, for example after a failed migration or with a corrupt file, recovery moves
/// its files, and any pending rehash files, into a `vault-primary.failed-open-<date>` folder next to it, then
/// starts a new, empty store. Nothing in the app ever reads those folders again. They're unencrypted copies of
/// the vault, which only someone with access to the device's files could use, but they may also hold the only
/// copy of some items. So they're never deleted automatically: only when the user deletes them from the
/// Backups page, or deletes all data. The one exception is a folder with nothing in it, which is removed when
/// it's found, since there's nothing in it to lose.
public struct PersistedLocalVaultStoreArchives: VaultStoreArchiving {
    /// The start of every archive folder's name.
    public static let directoryNamePrefix = "vault-primary.failed-open-"

    private let storageDirectory: URL

    public init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    public func archives() -> [VaultStoreArchive] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: keys,
        ) else {
            return []
        }
        return contents.compactMap { url -> VaultStoreArchive? in
            guard url.lastPathComponent.hasPrefix(Self.directoryNamePrefix),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true
            else {
                return nil
            }
            // Only a folder known to be empty goes: one that can't be read right now is kept.
            if let archivedFiles = try? fileManager.contentsOfDirectory(atPath: url.path(percentEncoded: false)),
               archivedFiles.isEmpty
            {
                try? fileManager.removeItem(at: url)
                return nil
            }
            let date = values.creationDate ?? values.contentModificationDate ?? .distantPast
            return VaultStoreArchive(url: url, date: date)
        }
        .sorted { $0.date < $1.date }
    }

    public func deleteAll() throws {
        for archive in archives() {
            try FileManager.default.removeItem(at: archive.url)
        }
    }
}
