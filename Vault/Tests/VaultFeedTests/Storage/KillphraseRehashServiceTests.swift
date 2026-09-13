import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

struct KillphraseRehashServiceTests {
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
            .init(itemID: id2, phrase: "beta"),
        ])
        let digester = makeDigester()

        await env.sut.run(using: digester)

        let calls = await env.recorder.calls
        #expect(calls.count == 2)
        let ids = calls.map(\.itemID).reducedToSet()
        #expect(ids == [id1, id2])
        // Each emitted digest must verify against its source phrase.
        let alpha = try #require(calls.first(where: { $0.itemID == id1 })?.digest)
        let beta = try #require(calls.first(where: { $0.itemID == id2 })?.digest)
        #expect(digester.matches(query: "alpha", salt: alpha.salt, digest: alpha.digest))
        #expect(digester.matches(query: "beta", salt: beta.salt, digest: beta.digest))
    }

    @Test
    func run_clearsPendingFileAfterAllEntriesWritten() async throws {
        let env = makeSUT()
        try env.pending.write([.init(itemID: UUID(), phrase: "kill")])
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
        try env.pending.write([.init(itemID: UUID(), phrase: "kill")])
        let digester = makeDigester()

        await env.sut.run(using: digester)
        await env.recorder.reset()
        await env.sut.run(using: digester)

        // Second run finds no pending entries.
        let calls = await env.recorder.calls
        #expect(calls.isEmpty)
    }
}

extension KillphraseRehashServiceTests {
    /// Actor-backed recorder so the `@Sendable` writer closure can
    /// collect invocations and consult the failing-id set without
    /// resorting to `@unchecked Sendable`.
    fileprivate actor WriterRecorder {
        struct Call {
            let itemID: UUID
            let digest: KillphraseDigest
        }

        private(set) var calls: [Call] = []
        private var failingIDs: Set<UUID> = []

        func setFailingIDs(_ ids: Set<UUID>) {
            failingIDs = ids
        }

        func reset() {
            calls.removeAll()
        }

        func record(itemID: UUID, digest: KillphraseDigest) throws {
            if failingIDs.contains(itemID) {
                throw TestError.simulated
            }
            calls.append(.init(itemID: itemID, digest: digest))
        }
    }

    fileprivate struct Env {
        let sut: KillphraseRehashService
        let pending: PendingKillphraseRehashStore
        let recorder: WriterRecorder
    }

    private func makeSUT() -> Env {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "pending-killphrase-\(UUID().uuidString).json",
        )
        let pending = PendingKillphraseRehashStore(fileURL: url)
        let recorder = WriterRecorder()
        let sut = KillphraseRehashService(
            pendingStore: pending,
            writer: { id, digest in
                try await recorder.record(itemID: id, digest: digest)
            },
        )
        return Env(sut: sut, pending: pending, recorder: recorder)
    }

    private func makeDigester() -> KillphraseDigester {
        let key = (try? KeyData<32>(data: Data(repeating: 0xAA, count: 32))) ?? .zero()
        return KillphraseDigester(key: key)
    }

    fileprivate enum TestError: Error {
        case simulated
    }
}
