import Foundation
import Synchronization
import Testing
@testable import VaultFeed

struct AppLockPasswordAttemptCounterTests {
    // MARK: - Counting

    @Test
    func remainingDelay_noAttempts_isZero() async throws {
        let (sut, _, _) = makeSUT()

        #expect(try await sut.remainingDelay() == .zero)
    }

    @Test
    func countAttempt_firstFour_haveNoDelay() async throws {
        let (sut, _, _) = makeSUT()

        for _ in 1 ... 4 {
            #expect(try await sut.countAttempt() == .counted(reachesEraseThreshold: false))
            #expect(try await sut.remainingDelay() == .zero)
        }
    }

    /// Counted before the password is tried, so force-quitting while the key is derived can't take the attempt back.
    @Test
    func countAttempt_savesTheCountBeforeReturning() async throws {
        let (sut, storage, clock) = makeSUT()

        _ = try await sut.countAttempt()

        #expect(storage.record == AppLockPasswordAttemptRecord(count: 1, latestAt: clock.now))
    }

    @Test
    func countAttempt_afterFiveWrong_waitsAMinute() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(5, with: sut, clock: clock)

        #expect(try await sut.remainingDelay() == .seconds(60))
        #expect(try await sut.countAttempt() == .delayed(.seconds(60)))

        clock.advance(by: .seconds(59))
        #expect(try await sut.countAttempt() == .delayed(.seconds(1)))

        clock.advance(by: .seconds(1))
        #expect(try await sut.countAttempt() == .counted(reachesEraseThreshold: false))
    }

    @Test
    func countAttempt_whileDelayed_isNotCounted() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(5, with: sut, clock: clock)
        let recordAfterFive = storage.record

        for _ in 1 ... 3 {
            clock.advance(by: .seconds(10))
            _ = try await sut.countAttempt()
        }

        #expect(storage.record == recordAfterFive)
        clock.advance(by: .seconds(30))
        _ = try await sut.countAttempt()
        #expect(try await sut.remainingDelay() == .seconds(5 * 60))
    }

    @Test
    func remainingDelay_countsDownFromTheLatestAttempt() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(6, with: sut, clock: clock)

        clock.advance(by: .seconds(100))

        #expect(try await sut.remainingDelay() == .seconds(5 * 60 - 100))
    }

    // MARK: - Schedule

    /// Wrong attempts in a row, and the minutes to wait after them.
    private static let schedule: [(attempts: Int, minutes: Int64)] = [
        (0, 0), (1, 0), (2, 0), (3, 0), (4, 0),
        (5, 1), (6, 5), (7, 15), (8, 15),
        (9, 60), (10, 60), (25, 60),
    ]

    @Test(arguments: schedule)
    func delay_followsTheIOSPasscodeSchedule(attempts: Int, minutes: Int64) {
        #expect(AppLockPasswordAttemptCounter.delay(afterAttempts: attempts) == .seconds(minutes * 60))
    }

    @Test
    func countAttempt_wrongAttemptsInARow_escalateTheDelay() async throws {
        let (sut, _, clock) = makeSUT()
        var delays = [Duration]()

        for _ in 1 ... 11 {
            try await makeAttempts(1, with: sut, clock: clock)
            try delays.append(await sut.remainingDelay())
        }

        let minutes: [Int64] = [0, 0, 0, 0, 1, 5, 15, 15, 60, 60, 60]
        #expect(delays == minutes.map { .seconds($0 * 60) })
    }

    // MARK: - Resetting

    @Test
    func reset_clearsTheCountAndTheDelay() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(6, with: sut, clock: clock)

        try await sut.reset()

        #expect(storage.record == nil)
        #expect(try await sut.remainingDelay() == .zero)
        try await makeAttempts(4, with: sut, clock: clock)
        #expect(try await sut.remainingDelay() == .zero)
        try await makeAttempts(1, with: sut, clock: clock)
        #expect(try await sut.remainingDelay() == .seconds(60))
    }

    @Test
    func reset_noAttempts_doesNothing() async throws {
        let (sut, storage, _) = makeSUT()

        try await sut.reset()

        #expect(storage.record == nil)
    }

    // MARK: - Relaunching

    @Test
    func relaunch_keepsTheDelay() async throws {
        let storage = InMemoryAppLockPasswordAttemptStorage()
        let clock = FakeAppLockClock()
        try await makeAttempts(5, with: makeSUT(storage: storage, clock: clock), clock: clock)
        clock.advance(by: .seconds(20))

        let relaunched = makeSUT(storage: storage, clock: clock)

        #expect(try await relaunched.remainingDelay() == .seconds(40))
        #expect(try await relaunched.countAttempt() == .delayed(.seconds(40)))
    }

    /// An attempt the app was stopped in the middle of, before it could reset, counts as a wrong one.
    @Test
    func relaunch_midAttempt_keepsTheAttemptCounted() async throws {
        let storage = InMemoryAppLockPasswordAttemptStorage()
        let clock = FakeAppLockClock()
        try await makeAttempts(4, with: makeSUT(storage: storage, clock: clock), clock: clock)
        _ = try await makeSUT(storage: storage, clock: clock).countAttempt()

        let relaunched = makeSUT(storage: storage, clock: clock)

        #expect(try await relaunched.remainingDelay() == .seconds(60))
    }

    // MARK: - Time going back

    /// The clock only goes back when the device restarts. However long it was off, the delay starts again in full.
    @Test
    func clockGoesBack_delayStartsAgainInFull() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(9, with: sut, clock: clock)
        clock.advance(by: .seconds(50 * 60))

        clock.goBack(by: .seconds(24 * 60 * 60))

        #expect(try await sut.remainingDelay() == .seconds(60 * 60))
        #expect(try await sut.countAttempt() == .delayed(.seconds(60 * 60)))
    }

    @Test
    func clockGoesBack_delayCountsDownFromWhenItWasNoticed() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(5, with: sut, clock: clock)
        clock.goBack(by: .seconds(3600))
        _ = try await sut.remainingDelay()

        clock.advance(by: .seconds(45))

        #expect(try await sut.remainingDelay() == .seconds(15))
        clock.advance(by: .seconds(15))
        #expect(try await sut.countAttempt() == .counted(reachesEraseThreshold: false))
        #expect(try await sut.remainingDelay() == .seconds(5 * 60))
    }

    /// Otherwise relaunching after a restart would start the delay again every time, while the clock is still behind.
    @Test
    func clockGoesBack_restartedDelayIsKeptAcrossRelaunches() async throws {
        let storage = InMemoryAppLockPasswordAttemptStorage()
        let clock = FakeAppLockClock()
        try await makeAttempts(5, with: makeSUT(storage: storage, clock: clock), clock: clock)
        clock.goBack(by: .seconds(3600))
        _ = try await makeSUT(storage: storage, clock: clock).remainingDelay()
        clock.advance(by: .seconds(45))

        let relaunched = makeSUT(storage: storage, clock: clock)

        #expect(try await relaunched.remainingDelay() == .seconds(15))
    }

    @Test
    func clockGoesBack_keepsTheCount() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(7, with: sut, clock: clock)

        clock.goBack(by: .seconds(3600))
        _ = try await sut.remainingDelay()

        #expect(storage.record?.count == 7)
    }

    // MARK: - Erase threshold

    @Test
    func countAttempt_tenthInARow_reachesTheEraseThreshold() async throws {
        let (sut, _, clock) = makeSUT()

        let attempts = try await makeAttempts(10, with: sut, clock: clock)

        #expect(attempts.dropLast().allSatisfy { $0 == .counted(reachesEraseThreshold: false) })
        #expect(attempts.last == .counted(reachesEraseThreshold: true))
    }

    /// The tenth attempt counts as wrong if the app was stopped before it finished, so the next one erases if it's
    /// wrong too: stopping the app can't buy an extra guess.
    @Test
    func countAttempt_afterAnUnfinishedTenth_stillReachesTheEraseThreshold() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(10, with: sut, clock: clock)

        let attempts = try await makeAttempts(2, with: sut, clock: clock)

        #expect(attempts == [.counted(reachesEraseThreshold: true), .counted(reachesEraseThreshold: true)])
    }

    @Test
    func countAttempt_afterReset_startsCountingToTheThresholdAgain() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(9, with: sut, clock: clock)

        try await sut.reset()

        let attempts = try await makeAttempts(9, with: sut, clock: clock)
        #expect(attempts.allSatisfy { $0 == .counted(reachesEraseThreshold: false) })
    }

    // MARK: - Storage failures

    @Test
    func countAttempt_countCannotBeSaved_throws() async {
        let storage = InMemoryAppLockPasswordAttemptStorage()
        storage.failsToSave = true
        let sut = makeSUT(storage: storage)

        await #expect(throws: InMemoryAppLockPasswordAttemptStorage.Failure.self) {
            try await sut.countAttempt()
        }
    }

    @Test
    func countAttempt_countCannotBeLoaded_throws() async {
        let storage = InMemoryAppLockPasswordAttemptStorage()
        storage.failsToLoad = true
        let sut = makeSUT(storage: storage)

        await #expect(throws: InMemoryAppLockPasswordAttemptStorage.Failure.self) {
            try await sut.countAttempt()
        }
        await #expect(throws: InMemoryAppLockPasswordAttemptStorage.Failure.self) {
            try await sut.remainingDelay()
        }
    }
}

// MARK: - Helpers

extension AppLockPasswordAttemptCounterTests {
    private func makeSUT() -> (
        AppLockPasswordAttemptCounter,
        InMemoryAppLockPasswordAttemptStorage,
        FakeAppLockClock,
    ) {
        let storage = InMemoryAppLockPasswordAttemptStorage()
        let clock = FakeAppLockClock()
        return (makeSUT(storage: storage, clock: clock), storage, clock)
    }

    /// A counter over `storage`. Making another over the same storage stands in for relaunching the app.
    private func makeSUT(
        storage: InMemoryAppLockPasswordAttemptStorage,
        clock: FakeAppLockClock = FakeAppLockClock(),
    ) -> AppLockPasswordAttemptCounter {
        AppLockPasswordAttemptCounter(storage: storage, clock: clock)
    }

    /// Makes `count` attempts in a row, none of them right, waiting out the delay before each.
    @discardableResult
    private func makeAttempts(
        _ count: Int,
        with sut: AppLockPasswordAttemptCounter,
        clock: FakeAppLockClock,
    ) async throws -> [AppLockPasswordAttempt] {
        var attempts = [AppLockPasswordAttempt]()
        for _ in 0 ..< count {
            try clock.advance(by: await sut.remainingDelay())
            try attempts.append(await sut.countAttempt())
        }
        return attempts
    }
}

/// Attempt storage held in memory. Like the keychain, it outlives the counters made over it.
private final class InMemoryAppLockPasswordAttemptStorage: AppLockPasswordAttemptStorage {
    struct Failure: Error {}

    private struct State {
        var record: AppLockPasswordAttemptRecord?
        var failsToLoad = false
        var failsToSave = false
    }

    private let state = Mutex(State())

    var record: AppLockPasswordAttemptRecord? {
        state.withLock(\.record)
    }

    var failsToLoad: Bool {
        get { state.withLock(\.failsToLoad) }
        set { state.withLock { $0.failsToLoad = newValue } }
    }

    var failsToSave: Bool {
        get { state.withLock(\.failsToSave) }
        set { state.withLock { $0.failsToSave = newValue } }
    }

    func load() throws -> AppLockPasswordAttemptRecord? {
        try state.withLock { state in
            guard !state.failsToLoad else { throw Failure() }
            return state.record
        }
    }

    func save(_ record: AppLockPasswordAttemptRecord) throws {
        try state.withLock { state in
            guard !state.failsToSave else { throw Failure() }
            state.record = record
        }
    }

    func remove() {
        state.withLock { $0.record = nil }
    }
}
