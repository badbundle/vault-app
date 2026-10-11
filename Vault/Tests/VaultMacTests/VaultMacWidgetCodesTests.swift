import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultFeed
@testable import VaultMac

/// Handing the widgets codes while the vault's unlocked, and taking them back as it locks (G98).
@MainActor
struct VaultMacWidgetCodesTests {
    @Test
    func update_whileUnlocked_handsOverTheCodesWidgetsMayShowAndReloadsThem() async throws {
        let code = MacTestItems.code(issuer: "Shown")
        let env = Environment(items: [code, MacTestItems.code(lockState: .lockedWithNativeSecurity)])

        env.sut.update()
        await env.sut.pendingUpdate?.value

        let handoff = try #require(env.store.current(at: env.now))
        #expect(handoff.items.map(\.id) == [code.id.rawValue])
        #expect(handoff.items.first?.issuer == "Shown")
        #expect(env.reloads.value == 1)
    }

    @Test
    func withdraw_takesTheCodesBackAtOnceAndReloads() async throws {
        let env = Environment(items: [MacTestItems.code()])
        env.sut.update()
        await env.sut.pendingUpdate?.value

        env.sut.withdraw()

        #expect(env.store.current(at: env.now) == nil)
        #expect(env.keychain.data.value == nil)
        #expect(env.reloads.value == 2)
    }

    @Test
    func update_whileLocked_handsNothingOverAndReadsNothing() async throws {
        let env = Environment(items: [MacTestItems.code()])
        env.isUnlocked.modify { $0 = false }

        env.sut.update()
        await env.sut.pendingUpdate?.value

        #expect(env.store.current(at: env.now) == nil)
        #expect(env.retrievals.value == 0)
    }

    /// Before the App Lock Password is first set, there's no vault, so nothing to hand over.
    @Test
    func update_withNoEncryptedVaultOpen_handsNothingOver() async throws {
        let env = Environment(items: nil)

        env.sut.update()
        await env.sut.pendingUpdate?.value

        #expect(env.store.current(at: env.now) == nil)
    }

    /// A lock while the codes are being worked out wins: they're never handed over.
    @Test
    func locking_whileTheCodesAreWorkedOut_handsNothingOver() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let env = Environment(items: [MacTestItems.code()], waitBeforeRetrieving: gate.stream)
        env.sut.update()
        let update = try #require(env.sut.pendingUpdate)

        env.isUnlocked.modify { $0 = false }
        env.sut.withdraw()
        gate.continuation.finish()
        await update.value

        #expect(env.store.current(at: env.now) == nil)
        #expect(env.keychain.data.value == nil)
    }

    /// Only the latest codes are handed over, however long earlier ones took to work out.
    @Test
    func update_again_handsOverOnlyTheLatestCodes() async throws {
        let gate = AsyncStream<Void>.makeStream()
        let env = Environment(items: [MacTestItems.code()], waitBeforeRetrieving: gate.stream)
        env.sut.update()
        let first = try #require(env.sut.pendingUpdate)
        let latest = MacTestItems.code(issuer: "Latest")
        env.items.modify { $0 = [latest] }
        env.waitBeforeRetrieving.modify { $0 = nil }

        env.sut.update()
        await env.sut.pendingUpdate?.value
        gate.continuation.finish()
        await first.value

        #expect(env.store.current(at: env.now)?.items.map(\.id) == [latest.id.rawValue])
    }

    /// While the vault stays unlocked, codes are handed over again halfway through each handoff's window, so they never
    /// run out.
    @Test
    func whileUnlocked_handsTheCodesOverAgainBeforeTheyRunOut() async throws {
        let env = Environment(items: [MacTestItems.code()], refresh: true)
        env.sut.update()
        await env.sut.pendingUpdate?.value
        let first = try #require(env.store.current(at: env.now))

        await env.sut.pendingRefresh?.value
        await env.sut.pendingUpdate?.value

        let second = try #require(env.store.current(at: env.now))
        #expect(second.id != first.id)
        #expect(env.sleeps.value.first == VaultMacWidgetCodes.refreshInterval)
        #expect(VaultMacWidgetCodes.refreshInterval == .seconds(WidgetCodeHandoff.window / 2))
    }

    /// If the codes can be neither deleted nor replaced, as while the Mac is locked, it tries again until it can.
    @Test
    func withdraw_failing_triesAgainUntilItCan() async throws {
        let env = Environment(items: [MacTestItems.code()])
        env.sut.update()
        await env.sut.pendingUpdate?.value
        env.keychain.fails.modify { $0 = true }

        env.sut.withdraw()
        env.keychain.fails.modify { $0 = false }
        await env.sut.pendingWithdrawal?.value

        #expect(env.store.current(at: env.now) == nil)
        #expect(env.keychain.data.value == nil)
        #expect(env.sleeps.value.contains(VaultMacWidgetCodes.withdrawalRetryInterval))
    }

    /// New codes replace any that couldn't be taken back, and trying again stops, so it never takes them back.
    @Test
    func handingOverAgain_stopsTryingToTakeTheOldCodesBack() async throws {
        let env = Environment(items: [MacTestItems.code()], retriesWait: true)
        env.keychain.fails.modify { $0 = true }
        env.sut.withdraw()
        let retrying = try #require(env.sut.pendingWithdrawal)
        env.keychain.fails.modify { $0 = false }

        env.sut.update()
        await env.sut.pendingUpdate?.value
        await retrying.value

        #expect(retrying.isCancelled)
        #expect(env.store.current(at: env.now) != nil)
    }

    /// An earlier run that stopped without locking, as when it crashed, may have left codes: they're taken back at
    /// launch.
    @Test
    func withdrawLeftovers_takesBackWhatAnEarlierRunLeft() throws {
        let env = Environment(items: [MacTestItems.code()])
        try env.store.publish(WidgetCodeHandoff(items: [MacTestItems.code()], now: env.now))

        env.sut.withdrawLeftovers()

        #expect(env.store.current(at: env.now) == nil)
        #expect(env.keychain.data.value == nil)
        #expect(env.reloads.value == 1)
    }
}

// MARK: - Helpers

extension VaultMacWidgetCodesTests {
    @MainActor
    private struct Environment {
        let now = MacTestItems.date
        let sut: VaultMacWidgetCodes
        let store: WidgetCodeHandoffStore
        let keychain = WidgetCodeKeychainSpy()
        let isUnlocked = SharedMutex(true)
        let items: SharedMutex<[VaultItem]?>
        let waitBeforeRetrieving: SharedMutex<AsyncStream<Void>?>
        let retrievals = SharedMutex(0)
        let reloads = SharedMutex(0)
        let sleeps = SharedMutex([Duration]())

        /// - Parameters:
        ///   - items: The open vault's items, or `nil` if no encrypted vault is open.
        ///   - waitBeforeRetrieving: Retrieving the items waits for it to finish.
        ///   - refresh: Whether the codes are handed over again once, after the first wait. Otherwise the wait lasts
        ///     until it's cancelled.
        ///   - retriesWait: Whether trying again to take the codes back waits until it's cancelled.
        init(
            items: [VaultItem]?,
            waitBeforeRetrieving: AsyncStream<Void>? = nil,
            refresh: Bool = false,
            retriesWait: Bool = false,
        ) {
            let items = SharedMutex(items)
            let waitBeforeRetrieving = SharedMutex(waitBeforeRetrieving)
            self.items = items
            self.waitBeforeRetrieving = waitBeforeRetrieving
            store = WidgetCodeHandoffStore(keychain: keychain)
            let isUnlocked = isUnlocked
            let retrievals = retrievals
            let reloads = reloads
            let sleeps = sleeps
            let now = now
            sut = VaultMacWidgetCodes(
                store: store,
                isUnlocked: { isUnlocked.value },
                retrieveItems: {
                    retrievals.modify { $0 += 1 }
                    if let wait = waitBeforeRetrieving.value {
                        for await _ in wait {}
                    }
                    return items.value
                },
                now: { now },
                sleep: { duration in
                    let refreshes = sleeps.modify { sleeps in
                        sleeps.append(duration)
                        return sleeps.count { $0 == VaultMacWidgetCodes.refreshInterval }
                    }
                    if duration == VaultMacWidgetCodes.refreshInterval {
                        // Only the first wait passes, if any, so the refreshes stop after one.
                        guard refresh, refreshes == 1 else {
                            try await suspendForever()
                            return
                        }
                    } else if retriesWait {
                        try await suspendForever()
                    }
                    try Task.checkCancellation()
                },
                reloadWidgets: { reloads.modify { $0 += 1 } },
            )
        }
    }
}

/// The handoff's keychain item, in memory, which can't be written to or deleted while it `fails`, as while the Mac is
/// locked.
private final class WidgetCodeKeychainSpy: WidgetKeychainStoring {
    struct Failure: Error {}

    let data = SharedMutex<Data?>(nil)
    let fails = SharedMutex(false)

    func read() throws -> Data? {
        data.value
    }

    func save(_ newData: Data) throws {
        guard !fails.value else { throw Failure() }
        data.modify { $0 = newData }
    }

    func remove() throws {
        guard !fails.value else { throw Failure() }
        data.modify { $0 = nil }
    }
}
