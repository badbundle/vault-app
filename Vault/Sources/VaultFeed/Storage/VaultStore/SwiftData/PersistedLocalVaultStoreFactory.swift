import Foundation
import SwiftData

public final class PersistedLocalVaultStoreFactory {
    public enum RecoveryMode: Equatable, Sendable {
        case recoverExistingStore
        case openOnly
    }

    private static let storeFilename = "vault-primary.sqlite"
    private static let storeSidecarSuffixes = ["-shm", "-wal"]

    private let storageDirectory: URL
    private let storeOpener: any PersistedLocalVaultStoreOpening
    private let fileSystem: any PersistedLocalVaultStoreRecoveryFileSystem
    private let archiveDirectoryName: () -> String
    private let recoveryMode: RecoveryMode
    private let failureHandler: (String) -> PersistedLocalVaultStore

    public init(
        storageDirectory: URL,
        fileManager: FileManager = .default,
        archiveDirectoryName: @escaping () -> String = {
            let timestamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            return PersistedLocalVaultStoreArchives.directoryNamePrefix + timestamp
        },
        recoveryMode: RecoveryMode = .recoverExistingStore,
    ) {
        self.storageDirectory = storageDirectory
        storeOpener = SwiftDataPersistedLocalVaultStoreOpener()
        fileSystem = FileManagerPersistedLocalVaultStoreRecoveryFileSystem(fileManager: fileManager)
        self.archiveDirectoryName = archiveDirectoryName
        self.recoveryMode = recoveryMode
        failureHandler = { fatalError($0) }
    }

    init(
        storageDirectory: URL,
        storeOpener: any PersistedLocalVaultStoreOpening,
        fileSystem: any PersistedLocalVaultStoreRecoveryFileSystem,
        archiveDirectoryName: @escaping () -> String,
        recoveryMode: RecoveryMode = .recoverExistingStore,
        failureHandler: @escaping (String) -> PersistedLocalVaultStore = { fatalError($0) },
    ) {
        self.storageDirectory = storageDirectory
        self.storeOpener = storeOpener
        self.fileSystem = fileSystem
        self.archiveDirectoryName = archiveDirectoryName
        self.recoveryMode = recoveryMode
        self.failureHandler = failureHandler
    }

    public func makeVaultStore() -> PersistedLocalVaultStore {
        do {
            return try makeVaultStoreOrThrow()
        } catch let StoreConnectionError.unableToConnect(error) {
            return failureHandler("Unable to connect to PersistedLocalVaultStore: \(error)")
        } catch let StoreConnectionError.unableToConnectAfterRecovery(error) {
            return failureHandler("Unable to connect to PersistedLocalVaultStore after recovery: \(error)")
        } catch let StoreConnectionError.unableToRecover(error) {
            return failureHandler("Unable to recover PersistedLocalVaultStore: \(error)")
        } catch {
            return failureHandler("Unable to connect to PersistedLocalVaultStore: \(error)")
        }
    }

    public func makeVaultStoreOrThrow() throws -> PersistedLocalVaultStore {
        let storeURL = storageDirectory.appending(path: Self.storeFilename)
        do {
            return try storeOpener.open(storeURL: storeURL)
        } catch {
            guard recoveryMode == .recoverExistingStore else {
                throw StoreConnectionError.unableToConnect(error)
            }
            try recoverExistingStoreIfPresent(storeURL: storeURL, connectionError: error)
            do {
                return try storeOpener.open(storeURL: storeURL)
            } catch {
                throw StoreConnectionError.unableToConnectAfterRecovery(error)
            }
        }
    }

    private func recoverExistingStoreIfPresent(storeURL _: URL, connectionError: any Error) throws {
        do {
            let existingURLs = storeBundleURLs().filter { fileExists(at: $0.url) }
            guard existingURLs.isEmpty == false else {
                throw StoreConnectionError.unableToConnect(connectionError)
            }

            let archiveURL = makeUniqueArchiveDirectoryURL()
            try fileSystem.createDirectory(at: archiveURL)

            for existingURL in existingURLs {
                let destinationURL = archiveURL.appending(path: existingURL.url.lastPathComponent)
                do {
                    try fileSystem.moveItem(at: existingURL.url, to: destinationURL)
                } catch {
                    guard fileExists(at: existingURL.url) else { continue }
                    throw StoreConnectionError.unableToRecover(error)
                }
            }
        } catch let error as StoreConnectionError {
            throw error
        } catch {
            throw StoreConnectionError.unableToRecover(error)
        }
    }

    enum StoreConnectionError: Error {
        case unableToConnect(any Error)
        case unableToRecover(any Error)
        case unableToConnectAfterRecovery(any Error)
    }

    struct NoUserDocumentDirectory: Error, LocalizedError {
        var errorDescription: String? {
            "No user document directory available"
        }
    }
}

extension PersistedLocalVaultStore {
    /// An empty in-memory store, for use as a safe fallback when the
    /// on-disk store cannot be opened: it keeps every consumer of the
    /// composition graph valid (app, autofill extension, rehash
    /// services) while guaranteeing nothing is written to the broken
    /// on-disk store.
    public static func inMemory() throws -> PersistedLocalVaultStore {
        let container = try ModelContainer(
            for: PersistedVaultItem.self, PersistedVaultTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true),
        )
        return PersistedLocalVaultStore(modelContainer: container)
    }
}

protocol PersistedLocalVaultStoreOpening {
    func open(storeURL: URL) throws -> PersistedLocalVaultStore
}

private struct SwiftDataPersistedLocalVaultStoreOpener: PersistedLocalVaultStoreOpening {
    func open(storeURL: URL) throws -> PersistedLocalVaultStore {
        let configuration = ModelConfiguration(
            "PersistedLocalVaultStore",
            schema: .init(versionedSchema: PersistedSchemaLatestVersion.self),
            url: storeURL,
        )
        let container = try ModelContainer(
            for: PersistedVaultItem.self, PersistedVaultTag.self,
            migrationPlan: PersistedSchemaMigrationPlan.self,
            configurations: configuration,
        )
        return PersistedLocalVaultStore(modelContainer: container)
    }
}

protocol PersistedLocalVaultStoreRecoveryFileSystem {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
}

private struct FileManagerPersistedLocalVaultStoreRecoveryFileSystem: PersistedLocalVaultStoreRecoveryFileSystem {
    let fileManager: FileManager

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path(percentEncoded: false))
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }
}

extension PersistedLocalVaultStoreFactory {
    /// The store's files in the directory: the SQLite database first, then its write-ahead log and shared memory.
    static func storeFileURLs(storageDirectory: URL) -> [URL] {
        let storeURL = storageDirectory.appending(path: storeFilename)
        return [storeURL] + storeSidecarSuffixes.map { suffix in
            URL(fileURLWithPath: storeURL.path(percentEncoded: false) + suffix)
        }
    }

    /// The pending rehash files that a schema migration leaves next to the store (see `KillphraseRehashService`).
    static func pendingRehashFileURLs(storageDirectory: URL) -> [URL] {
        [
            PendingKillphraseRehashStore.defaultURL(storeDirectory: storageDirectory),
            PendingSearchPassphraseRehashStore.defaultURL(storeDirectory: storageDirectory),
        ]
    }

    private func makeUniqueArchiveDirectoryURL() -> URL {
        let baseName = archiveDirectoryName()
        var candidateURL = storageDirectory.appending(path: baseName)
        var suffix = 2

        while fileExists(at: candidateURL) {
            candidateURL = storageDirectory.appending(path: "\(baseName)-\(suffix)")
            suffix += 1
        }

        return candidateURL
    }

    private func storeBundleURLs() -> [RecoveryFile] {
        let storeURLs = Self.storeFileURLs(storageDirectory: storageDirectory)
        let rehashURLs = Self.pendingRehashFileURLs(storageDirectory: storageDirectory)
        return ([storeURLs[0]] + rehashURLs + storeURLs.dropFirst()).map(RecoveryFile.init(url:))
    }

    private func fileExists(at url: URL) -> Bool {
        fileSystem.fileExists(at: url)
    }

    private struct RecoveryFile {
        let url: URL
    }
}
