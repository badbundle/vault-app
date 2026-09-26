import Foundation
import Testing
@testable import VaultFeed

struct PendingKillphraseRehashStoreTests {
    @Test
    func read_returnsEmptyWhenFileMissing() throws {
        let sut = makeSUT(at: tmpURL())

        let entries = try sut.read()

        #expect(entries.isEmpty)
    }

    @Test
    func writeThenRead_roundTripsEntries() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sut = makeSUT(at: url)
        let entries: [PendingKillphraseRehashStore.Entry] = [
            .init(itemID: UUID(), phrase: "kill1"),
            .init(itemID: UUID(), phrase: "kill2"),
        ]

        try sut.write(entries)
        let read = try sut.read()

        #expect(read == entries)
    }

    @Test
    func write_overwritesExistingFile() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sut = makeSUT(at: url)
        let first: [PendingKillphraseRehashStore.Entry] = [.init(itemID: UUID(), phrase: "old")]
        let second: [PendingKillphraseRehashStore.Entry] = [.init(itemID: UUID(), phrase: "new")]

        try sut.write(first)
        try sut.write(second)
        let read = try sut.read()

        #expect(read == second)
    }

    @Test
    func clear_removesFile() throws {
        let url = tmpURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sut = makeSUT(at: url)
        try sut.write([.init(itemID: UUID(), phrase: "kill")])

        try sut.clear()

        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == false)
        #expect(try sut.read().isEmpty)
    }

    @Test
    func clear_isNoOpWhenFileMissing() throws {
        let sut = makeSUT(at: tmpURL())

        // Must not throw on missing file.
        try sut.clear()
    }
}

extension PendingKillphraseRehashStoreTests {
    private func makeSUT(at url: URL) -> PendingKillphraseRehashStore {
        PendingKillphraseRehashStore(fileURL: url)
    }

    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "pending-killphrase-\(UUID().uuidString).json")
    }
}
