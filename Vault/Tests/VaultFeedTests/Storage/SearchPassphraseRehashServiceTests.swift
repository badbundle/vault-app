import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

struct SearchPassphraseRehashServiceTests {
    @Test
    func run_isNoOpWhenPendingEmpty() async {
        let env = makeSUT()
        let digester = makeDigester()

        await env.sut.run(using: digester)

        let calls = await env.recorder.calls
        #expect(calls.isEmpty)
    }

    @Test
    func run_writesDigestPerPendingEntry() async throws {
        let env = makeSUT()
        let id1 = UUID()
        let id2 = UUID()
        try env.pending.write([
            .init(itemID: id1, phrase: "alpha"),
            .init(itemID: id2, phrase: "Beta"),
        ])
        let digester = makeDigester()

        await env.sut.run(using: digester)

        let calls = await env.recorder.calls
        #expect(calls.count == 2)
        let ids = calls.map(\.itemID).reducedToSet()
        #expect(ids == [id1, id2])
        // Each emitted digest must verify against its source phrase, and
        // must remain case-insensitive (the digester folds the input).
        let alpha = try #require(calls.first(where: { $0.itemID == id1 })?.digest)
        let beta = try #require(calls.first(where: { $0.itemID == id2 })?.digest)
        #expect(digester.matches(query: "alpha", salt: alpha.salt, digest: alpha.digest))
        #expect(digester.matches(query: "ALPHA", salt: alpha.salt, digest: alpha.digest))
        #expect(digester.matches(query: "beta", salt: beta.salt, digest: beta.digest))
    }

    @Test
    func run_clearsPendingFileAfterAllEntriesWritten() async throws {
        let env = makeSUT()
        try env.pending.write([.init(itemID: UUID(), phrase: "phrase")])
        let digester = makeDigester()

        await env.sut.run(using: digester)

        #expect(try env.pending.read().isEmpty)
    }

    @Test
    func run_keepsFailedEntriesInPendingForRetry() async throws {
        let env = makeSUT()
        let goodID = UUID()
        let badID = UUID()
        try env.pending.write([
            .init(itemID: goodID, phrase: "good"),
            .init(itemID: badID, phrase: "bad"),
        ])
        await env.recorder.setFailingIDs([badID])
        let digester = makeDigester()

        await env.sut.run(using: digester)

        let remaining = try env.pending.read()
        #expect(remaining.count == 1)
        #expect(remaining.first?.itemID == badID)
        #expect(remaining.first?.phrase == "bad")
    }

    @Test
    func run_isIdempotentWhenInvokedAfterSuccess() async throws {
        let env = makeSUT()
        try env.pending.write([.init(itemID: UUID(), phrase: "phrase")])
        let digester = makeDigester()

        await env.sut.run(using: digester)
        await env.recorder.reset()
        await env.sut.run(using: digester)

        let calls = await env.recorder.calls
        #expect(calls.isEmpty)
    }
}

extension SearchPassphraseRehashServiceTests {
    fileprivate actor WriterRecorder {
        struct Call {
            let itemID: UUID
            let digest: SearchPassphraseDigest
        }

        private(set) var calls: [Call] = []
        private var failingIDs: Set<UUID> = []

        func setFailingIDs(_ ids: Set<UUID>) {
            failingIDs = ids
        }

        func reset() {
            calls.removeAll()
        }

        func record(itemID: UUID, digest: SearchPassphraseDigest) throws {
            if failingIDs.contains(itemID) {
                throw TestError.simulated
            }
            calls.append(.init(itemID: itemID, digest: digest))
        }
    }

    fileprivate struct Env {
        let sut: SearchPassphraseRehashService
        let pending: PendingSearchPassphraseRehashStore
        let recorder: WriterRecorder
    }

    private func makeSUT() -> Env {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "pending-search-passphrase-\(UUID().uuidString).json",
        )
        let pending = PendingSearchPassphraseRehashStore(fileURL: url)
        let recorder = WriterRecorder()
        let sut = SearchPassphraseRehashService(
            pendingStore: pending,
            writer: { id, digest in
                try await recorder.record(itemID: id, digest: digest)
            },
        )
        return Env(sut: sut, pending: pending, recorder: recorder)
    }

    private func makeDigester() -> SearchPassphraseDigester {
        let key = (try? KeyData<32>(data: Data(repeating: 0xBB, count: 32))) ?? .zero()
        return SearchPassphraseDigester(key: key)
    }

    fileprivate enum TestError: Error {
        case simulated
    }
}
