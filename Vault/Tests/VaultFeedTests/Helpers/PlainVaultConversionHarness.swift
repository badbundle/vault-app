import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

/// A plain SQLite store in a directory of its own, a store session reading it, and a converter to encrypt it: as
/// the app has them when the App Lock Password is first set.
///
/// Every file operation the conversion makes goes through `fileSystem`, so tests can make any step fail or crash.
struct PlainVaultConversionHarness {
    static let password = "correct horse battery staple"
    static let unlockDeadline = Duration.seconds(1)

    let directory: URL
    let store: PersistedLocalVaultStore
    let session: VaultStoreSession
    let fileSystem: FaultInjectingSlotFileSystem
    /// What the attempt counter and the conversion's hooks did, in order.
    let log: SharedMutex<[String]>
    let attemptStorage: LoggingAttemptStorage
    /// Where the conversion's wrap is stamped, in memory.
    let wrapStamp = InMemoryWrapStampStorage()
    let converter: VaultEncryptionConverter

    /// - Parameters:
    ///   - openedNormally: Whether the plain store opened normally, rather than as an empty fallback.
    ///   - releasingPlainStore: Runs when the converter lets go of the plain store, after the commit.
    ///   - clearingCredentialIdentities: Runs when the converter clears the QuickType identity store.
    init(
        directory: URL,
        openedNormally: Bool = true,
        releasingPlainStore: @escaping @Sendable (VaultStoreSession) async -> Void = { _ in },
        clearingCredentialIdentities: @escaping @Sendable () -> Void = {},
    ) throws {
        let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
        try self.init(
            directory: directory,
            store: store,
            openedNormally: openedNormally,
            releasingPlainStore: releasingPlainStore,
            clearingCredentialIdentities: clearingCredentialIdentities,
        )
    }

    init(
        directory: URL,
        store: PersistedLocalVaultStore,
        openedNormally: Bool = true,
        releasingPlainStore: @escaping @Sendable (VaultStoreSession) async -> Void = { _ in },
        clearingCredentialIdentities: @escaping @Sendable () -> Void = {},
    ) throws {
        let session = VaultStoreSession(target: .plain(store))
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: LiveSlotFileSystem())
        let log = SharedMutex([String]())
        let attemptStorage = LoggingAttemptStorage(log: log)
        self.directory = directory
        self.store = store
        self.session = session
        self.fileSystem = fileSystem
        self.log = log
        self.attemptStorage = attemptStorage
        let wrapStamper = VaultDeviceWrapStamper.inMemory(storage: wrapStamp)
        converter = VaultEncryptionConverter(
            directory: directory,
            fileSystem: fileSystem,
            plainStore: store,
            plainStoreOpenedNormally: openedNormally,
            session: session,
            archives: PersistedLocalVaultStoreArchives(storageDirectory: directory),
            attemptCounter: AppLockPasswordAttemptCounter(storage: attemptStorage, clock: FakeAppLockClock()),
            hooks: VaultEncryptionConverter.Hooks(
                releasePlainStore: {
                    log.modify { $0.append("release the plain store") }
                    await releasingPlainStore(session)
                },
                clearCredentialIdentities: {
                    log.modify { $0.append("clear QuickType") }
                    clearingCredentialIdentities()
                },
                reloadWidgets: { log.modify { $0.append("reload widgets") } },
            ),
            calibrate: {
                AppLockKeyDerivationCalibration(
                    parameters: EncryptedVaultFixture.kdfParameters,
                    expectedDerivationDuration: .milliseconds(10),
                    unlockDeadline: Self.unlockDeadline,
                )
            },
            wrapStamper: wrapStamper,
        )
    }

    func encrypt(deletingArchives: Bool = false) async throws {
        try await converter.encrypt(password: Self.password, deletingArchives: deletingArchives)
    }

    // MARK: - What's on disk

    var stateFile: VaultStorageStateFile {
        VaultStorageStateFile(directory: directory, fileSystem: LiveSlotFileSystem())
    }

    func fileNames() throws -> Set<String> {
        try Set(FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))
    }

    /// Whether any of the plain store's files, or its pending rehash files, are there.
    func plainStoreFilesExist() throws -> Bool {
        let names = try fileNames()
        let plainFiles = PersistedLocalVaultStoreFactory.storeFileURLs(storageDirectory: directory)
            + PersistedLocalVaultStoreFactory.pendingRehashFileURLs(storageDirectory: directory)
        return plainFiles.contains { names.contains($0.lastPathComponent) }
    }

    /// The encrypted vault the password opens: its slot, and its records.
    func openEncryptedVault() async throws -> (slot: Int, state: VaultRecordState)? {
        guard let contents = try await EncryptedVaultFile(directory: directory).open() else { return nil }
        let key = try contents.header.passwordKey(for: Self.password)
        let opened = VaultSlotFile.slotIndices.compactMap { try? contents.openSlot($0, with: key) }
        let slot = try #require(opened.first)
        #expect(opened.count == 1)
        return try (slot.index, EncryptedVaultPayload.decode(slot: slot, in: contents))
    }

    /// Launches again: recovers from any change underway, as the app does, then reads the vault from wherever it's
    /// stored now.
    func relaunch() async throws -> (mode: VaultStorageState.Mode, state: VaultRecordState) {
        let recovery = VaultStorageRecovery(directory: directory)
        let mode = try recovery.recoverAtLaunch()
        try await recovery.finishClearingSystemSurfaces { [log] in
            log.modify { $0.append("clear the system surfaces at launch") }
        }
        switch mode {
        case .plain:
            let reopened = try PersistedLocalVaultStoreFactory(storageDirectory: directory, recoveryMode: .openOnly)
                .makeVaultStoreOrThrow()
            return try await (.plain, reopened.recordState())
        case .password:
            let vault = try #require(try await openEncryptedVault())
            return (.password, vault.state)
        }
    }
}
