import Foundation

/// Persisted as a sibling of the SwiftData store during the V1 → V2 schema
/// migration. Records the plaintext killphrases that were dropped from the
/// schema in Phase A so they can be hashed and written back in Phase B
/// (after the vault key becomes available on first post-update unlock).
///
/// On disk this is a JSON file written with file protection
/// `.completeFileProtectionUntilFirstUserAuthentication`. It only exists
/// between a successful schema migration and the first
/// `KillphraseRehashService.run` after it, at the same launch, and it's
/// deleted as soon as every entry has been re-hashed.
///
/// `FileManager` is documented thread-safe for the basic operations used
/// here (`fileExists`, `attributesOfItem`, `removeItem`) and the call
/// sites only ever hop through this struct serially via the rehash
/// service. Marked `@unchecked Sendable` so the injected dependency does
/// not force every caller to wrap it.
struct PendingKillphraseRehashStore: @unchecked Sendable { // swiftlint:disable:this no_unchecked_sendable
    struct Entry: Codable, Equatable {
        let itemID: UUID
        let phrase: String
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let protectedWrite: (Data, URL) throws -> Void

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        protectedWrite: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        },
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.protectedWrite = protectedWrite
    }

    /// Default location alongside the SwiftData store.
    static func defaultURL(storeDirectory: URL) -> URL {
        storeDirectory.appending(path: "vault-primary.pending-killphrase-rehash.json")
    }

    /// Read all pending entries. Returns an empty array if no file exists.
    func read() throws -> [Entry] {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard data.isEmpty == false else { return [] }
        return try JSONDecoder().decode([Entry].self, from: data)
    }

    /// Write a snapshot. Overwrites any existing file. File protection is
    /// applied so the data is unreadable until the user has authenticated
    /// the device at least once after boot.
    func write(_ entries: [Entry]) throws {
        let data = try JSONEncoder().encode(entries)
        try protectedWrite(data, fileURL)
    }

    /// Deletes the file.
    ///
    /// There's no point overwriting it first. An atomic write of zeros
    /// makes a new file and renames it over this one, so it never touches
    /// the old blocks; and on iOS each file's contents are encrypted with a
    /// key kept in its own metadata, which goes when the file is deleted.
    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }
}
