import CryptoEngine
import CryptoKit
import Foundation
import Testing
@testable import VaultFeed

/// An encrypted vault file with one vault in it, for tests.
struct EncryptedVaultFixture {
    /// Where the file is, through the file system the fixture was made with.
    let file: EncryptedVaultFile
    let slotIndex: Int
    let rootKey: VaultSlotRootKey

    /// Cheap Argon2id parameters. Nothing derives with them, but the header has to carry some.
    static let kdfParameters = Argon2idParameters(memoryKiB: 64, iterations: 1, parallelism: 1)

    /// A directory for an in-memory file system.
    static let inMemoryDirectory = URL(filePath: "/vault", directoryHint: .isDirectory)

    /// Writes a new file with a vault holding `state` in a random slot, and every other slot random.
    ///
    /// It writes the file with `fileSystem` directly, so a fault-injecting file system only sees what the test
    /// does afterwards.
    init(
        fileSystem: any SlotFileSystem = InMemorySlotFileSystem(),
        directory: URL = inMemoryDirectory,
        state: VaultRecordState = .empty,
        slotIndex: Int = VaultSlotFile.slotIndices.randomElement()!,
        payloadVersion: UInt32 = EncryptedVaultPayload.currentVersion,
    ) throws {
        var contents = try VaultSlotFile(kdfParameters: Self.kdfParameters)
        let rootKey = VaultSlotRootKey.password(derivedKey: SymmetricKey(size: .bits256))
        var payload = try EncryptedVaultPayload.encode(state)
        payload.version = payloadVersion
        try contents.createVault(inSlot: slotIndex, rootKey: rootKey, payload: payload, wrappedAt: Date())
        try fileSystem.createFile(at: directory.appending(path: EncryptedVaultFile.fileName), contents: contents.bytes)
        self.init(
            file: EncryptedVaultFile(directory: directory, fileSystem: fileSystem),
            slotIndex: slotIndex,
            rootKey: rootKey,
        )
    }

    private init(file: EncryptedVaultFile, slotIndex: Int, rootKey: VaultSlotRootKey) {
        self.file = file
        self.slotIndex = slotIndex
        self.rootKey = rootKey
    }

    /// Creates another vault, holding `state`, in another slot of the same file.
    func addingVault(inSlot index: Int, state: VaultRecordState = .empty) throws -> EncryptedVaultFixture {
        let rootKey = VaultSlotRootKey.password(derivedKey: SymmetricKey(size: .bits256))
        try file.withLock { file in
            var contents = try #require(try file.read())
            try contents.createVault(
                inSlot: index,
                rootKey: rootKey,
                payload: EncryptedVaultPayload.encode(state),
                wrappedAt: Date(),
            )
            try file.write(contents) { _ in }
        }
        return EncryptedVaultFixture(file: file, slotIndex: index, rootKey: rootKey)
    }

    /// The same vault, through another file system: for example one that injects faults.
    func through(_ fileSystem: any SlotFileSystem) -> EncryptedVaultFixture {
        EncryptedVaultFixture(
            file: EncryptedVaultFile(directory: file.directory, fileSystem: fileSystem),
            slotIndex: slotIndex,
            rootKey: rootKey,
        )
    }

    /// Unlocks the vault as the unlock service will: opens the file, then the slot with its key.
    func openStore(
        sortOrder: VaultStoreSortOrder = .relativeOrder,
        currentDate: @escaping @Sendable () -> Date = { Date() },
    ) throws -> EncryptedVaultStore {
        let contents = try #require(try file.open())
        return try EncryptedVaultStore(
            file: file,
            contents: contents,
            slot: contents.openSlot(slotIndex, with: rootKey),
            sortOrder: sortOrder,
            currentDate: currentDate,
        )
    }

    /// The file's bytes on disk now.
    func bytes() throws -> Data {
        try #require(try file.fileSystem.contents(of: file.url))
    }

    /// The vault as it's saved on disk now.
    func savedState() throws -> VaultRecordState {
        let contents = try VaultSlotFile(bytes: bytes())
        return try EncryptedVaultPayload.decode(contents.openPayload(of: contents.openSlot(slotIndex, with: rootKey)))
    }

    /// The slot as it's saved on disk now.
    func savedSlot() throws -> VaultSlotFile.OpenedSlot {
        try VaultSlotFile(bytes: bytes()).openSlot(slotIndex, with: rootKey)
    }

    /// The names of the temp files in the directory.
    func temporaryFileNames() throws -> [String] {
        try file.fileSystem.contentsOfDirectory(at: file.directory)
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix(EncryptedVaultFile.temporaryFilePrefix) }
    }
}

/// Runs `body` with a new, empty directory on disk, and deletes it afterwards.
func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = URL.temporaryDirectory.appending(
        path: "EncryptedVault-\(UUID().uuidString)",
        directoryHint: .isDirectory,
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}
