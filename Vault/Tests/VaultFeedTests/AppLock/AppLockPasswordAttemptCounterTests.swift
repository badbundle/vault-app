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

    // MARK: - Opening a vault

    /// The record stays, with none in a row and the attempt that opened the vault taken back off the recent count.
    @Test
    func noteRightAttempt_clearsTheCountInARowAndTakesItselfOffTheRecentCount() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(6, with: sut, clock: clock)
        let latestAt = clock.now

        try await sut.noteRightAttempt()

        #expect(storage.record?.count == .zero)
        #expect(storage.record?.recentWrong == 5)
        #expect(storage.record?.latestAt == latestAt)
        #expect(try await !sut.hasReachedEraseThreshold())
    }

    @Test
    func noteRightAttempt_noAttempts_doesNothing() async throws {
        let (sut, storage, _) = makeSUT()

        try await sut.noteRightAttempt()

        #expect(storage.record == nil)
    }

    /// After an attempt that opened a vault, the next can be made at once, however many wrong ones came before. It
    /// waits as long after it, if it's wrong, as it would have without the right one.
    @Test
    func noteRightAttempt_theNextAttemptNeedntWait() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(10, with: sut, clock: clock)
        try await sut.noteRightAttempt()

        #expect(try await sut.remainingDelay() == .zero)
        #expect(try await sut.countAttempt() == .counted(reachesEraseThreshold: false))
        #expect(try await sut.remainingDelay() == .seconds(60 * 60))
    }

    /// Opening a vault between wrong attempts, the real one or a duress one, doesn't stop the delays growing: they
    /// follow the recent count, which only goes down with time.
    @Test
    func countAttempt_wrongAttemptsEitherSideOfARightOne_keepEscalatingTheDelay() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(5, with: sut, clock: clock)
        try await sut.noteRightAttempt()

        var delays = [Duration]()
        for _ in 1 ... 5 {
            try await makeAttempts(1, with: sut, clock: clock)
            try delays.append(await sut.remainingDelay())
        }

        let minutes: [Int64] = [1, 5, 15, 15, 60]
        #expect(delays == minutes.map { .seconds($0 * 60) })
    }

    /// The count in a row still starts again whenever a vault opens, so only wrong attempts in a row erase (VAULT-34).
    @Test
    func countAttempt_rightAttemptsBetweenWrongOnes_neverReachTheEraseThreshold() async throws {
        let (sut, _, clock) = makeSUT()

        var attempts = [AppLockPasswordAttempt]()
        for _ in 1 ... 3 {
            try await attempts += makeAttempts(
                AppLockPasswordAttemptCounter.eraseThreshold - 1,
                with: sut,
                clock: clock,
            )
            try await sut.noteRightAttempt()
        }

        #expect(attempts.allSatisfy { $0 == .counted(reachesEraseThreshold: false) })
        #expect(try await !sut.hasReachedEraseThreshold())
    }

    // MARK: - The recent count

    /// It goes down by one for every hour that passes, and what's left of an hour carries over.
    @Test
    func recentWrong_goesDownByOneAnHour() async throws {
        let (sut, storage, clock) = makeSUT()
        let start = clock.now
        try await makeAttempts(4, with: sut, clock: clock)

        clock.advance(by: .seconds(150 * 60))
        try await makeAttempts(1, with: sut, clock: clock)

        #expect(storage.record?.recentWrong == 3)
        #expect(storage.record?.recentWrongAt == start.advanced(by: .seconds(120 * 60)))

        clock.advance(by: .seconds(30 * 60))
        try await makeAttempts(1, with: sut, clock: clock)

        #expect(storage.record?.recentWrong == 3)
        #expect(storage.record?.recentWrongAt == start.advanced(by: .seconds(180 * 60)))
    }

    /// So the delays shorten with time, whenever the count in a row started again.
    @Test
    func countAttempt_hoursAfterWrongAttempts_waitsLess() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(9, with: sut, clock: clock)
        try await sut.noteRightAttempt()

        clock.advance(by: .seconds(5 * 60 * 60))
        try await makeAttempts(1, with: sut, clock: clock)

        #expect(try await sut.remainingDelay() == .zero)
    }

    /// For the password turned back on after it was off: the count in a row starts again, but the recent count and its
    /// delays stay.
    @Test
    func resetCountInARow_keepsTheRecentCount() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(8, with: sut, clock: clock)

        try await sut.resetCountInARow()

        #expect(storage.record?.count == .zero)
        #expect(storage.record?.recentWrong == 8)
        try await makeAttempts(1, with: sut, clock: clock)
        #expect(try await sut.remainingDelay() == .seconds(60 * 60))
    }

    @Test
    func resetCountInARow_noAttempts_doesNothing() async throws {
        let (sut, storage, _) = makeSUT()

        try await sut.resetCountInARow()

        #expect(storage.record == nil)
    }

    /// A record saved before the recent count was kept has only the count in a row. Every attempt in it reads as
    /// recent: a record was only kept then until a vault opened.
    @Test
    func recordFromBefore_readsWithEveryAttemptRecent() async throws {
        struct RecordFromBefore: Encodable {
            var count: Int
            var latestAt: ContinuousClock.Instant
        }
        let clock = FakeAppLockClock()
        let data = try JSONEncoder().encode(RecordFromBefore(count: 6, latestAt: clock.now))

        let record = try JSONDecoder().decode(AppLockPasswordAttemptRecord.self, from: data)

        #expect(record == AppLockPasswordAttemptRecord(
            count: 6,
            latestAt: clock.now,
            recentWrong: 6,
            recentWrongAt: clock.now,
        ))
        let storage = InMemoryAppLockPasswordAttemptStorage()
        storage.record = record
        let sut = makeSUT(storage: storage, clock: clock)
        #expect(try await sut.remainingDelay() == .seconds(5 * 60))
        clock.advance(by: .seconds(5 * 60))
        _ = try await sut.countAttempt()
        try await sut.noteRightAttempt()
        #expect(storage.record?.count == .zero)
        #expect(storage.record?.recentWrong == 6)
    }

    @Test
    func record_keepsTheRecentCountWhenSaved() throws {
        let clock = FakeAppLockClock()
        let record = AppLockPasswordAttemptRecord(
            count: 2,
            latestAt: clock.now,
            recentWrong: 7,
            recentWrongAt: clock.now.advanced(by: .seconds(-90)),
        )

        let decoded = try JSONDecoder().decode(AppLockPasswordAttemptRecord.self, from: JSONEncoder().encode(record))

        #expect(decoded == record)
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
        #expect(storage.record?.recentWrong == 7)
    }

    /// However long the device was off, none of it takes the recent count down: it goes down only from when the clock
    /// was found to have gone back.
    @Test
    func clockGoesBack_recentCountGoesDownOnlyFromThen() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(4, with: sut, clock: clock)
        clock.advance(by: .seconds(3 * 60 * 60))

        clock.goBack(by: .seconds(24 * 60 * 60))
        try await makeAttempts(1, with: sut, clock: clock)

        #expect(storage.record?.recentWrong == 5)
        #expect(storage.record?.recentWrongAt == clock.now)

        clock.advance(by: .seconds(60 * 60))
        try await makeAttempts(1, with: sut, clock: clock)

        #expect(storage.record?.recentWrong == 5)
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

    // MARK: - Other processes

    /// The app and the AutoFill extension can count attempts at the same time, as on an iPad, so every read and write
    /// of the record happens with no other process able to.
    @Test
    func everyChange_holdsExclusiveAccessToTheRecord() async throws {
        let (sut, storage, clock) = makeSUT()

        try await makeAttempts(6, with: sut, clock: clock)
        try await sut.noteRightAttempt()
        try await makeAttempts(1, with: sut, clock: clock)
        try await sut.resetCountInARow()
        try await sut.reset()

        #expect(storage.accessesOutsideExclusiveAccess == 0)
    }

    // MARK: - An erase that's due

    @Test
    func hasReachedEraseThreshold_onceTenAreCounted() async throws {
        let (sut, _, clock) = makeSUT()

        var answers = try await [sut.hasReachedEraseThreshold()]
        for _ in 0 ..< 11 {
            try await makeAttempts(1, with: sut, clock: clock)
            try await answers.append(sut.hasReachedEraseThreshold())
        }

        #expect(answers == Array(repeating: false, count: 10) + [true, true])
    }

    @Test
    func hasReachedEraseThreshold_countsNothingAndHoldsExclusiveAccess() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(10, with: sut, clock: clock)
        let record = storage.record

        _ = try await sut.hasReachedEraseThreshold()

        #expect(storage.record == record)
        #expect(storage.accessesOutsideExclusiveAccess == 0)
    }

    @Test
    func hasReachedEraseThreshold_afterReset_isFalse() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(10, with: sut, clock: clock)

        try await sut.reset()

        #expect(try await !sut.hasReachedEraseThreshold())
    }

    // MARK: - Stopping before the erase threshold

    /// As AutoFill counts: the first nine as usual, then it stops at the tenth, which could erase.
    @Test
    func countAttempt_stoppingBeforeEraseThreshold_countsNineThenStops() async throws {
        let (sut, _, clock) = makeSUT()

        var attempts = [AppLockPasswordAttempt]()
        for _ in 0 ..< 10 {
            clock.advance(by: .seconds(60 * 60))
            try await attempts.append(sut.countAttempt(stoppingBeforeEraseThreshold: true))
        }

        #expect(attempts.dropLast().allSatisfy { $0 == .counted(reachesEraseThreshold: false) })
        #expect(attempts.last == .stoppedBeforeEraseThreshold)
    }

    /// Nothing is counted and no delay starts, so the app's next attempt is still the tenth.
    @Test
    func countAttempt_stoppedBeforeEraseThreshold_countsNothing() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(9, with: sut, clock: clock)
        clock.advance(by: .seconds(60 * 60))
        let record = storage.record

        let attempt = try await sut.countAttempt(stoppingBeforeEraseThreshold: true)

        #expect(attempt == .stoppedBeforeEraseThreshold)
        #expect(storage.record == record)
        #expect(try await sut.countAttempt() == .counted(reachesEraseThreshold: true))
    }

    /// That attempt will never be tried there, so it stops without saying how long to wait.
    @Test
    func countAttempt_stoppingBeforeEraseThreshold_whileWaiting_stops() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(9, with: sut, clock: clock)

        #expect(try await sut.countAttempt(stoppingBeforeEraseThreshold: true) == .stoppedBeforeEraseThreshold)
    }

    /// Past it too: after a tenth attempt the app was stopped in the middle of, every wrong attempt can erase.
    @Test
    func countAttempt_stoppingBeforeEraseThreshold_pastIt_stops() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(10, with: sut, clock: clock)
        clock.advance(by: .seconds(60 * 60))

        #expect(try await sut.countAttempt(stoppingBeforeEraseThreshold: true) == .stoppedBeforeEraseThreshold)
    }

    @Test
    func countAttempt_stoppingBeforeEraseThreshold_afterReset_counts() async throws {
        let (sut, _, clock) = makeSUT()
        try await makeAttempts(9, with: sut, clock: clock)

        try await sut.reset()

        let attempt = try await sut.countAttempt(stoppingBeforeEraseThreshold: true)
        #expect(attempt == .counted(reachesEraseThreshold: false))
    }

    /// The count is read and the decision made while no other process can count, so an attempt the app counts at
    /// the same moment can't make AutoFill's the tenth.
    @Test
    func countAttempt_stoppingBeforeEraseThreshold_holdsExclusiveAccess() async throws {
        let (sut, storage, clock) = makeSUT()
        try await makeAttempts(9, with: sut, clock: clock)

        _ = try await sut.countAttempt(stoppingBeforeEraseThreshold: true)

        #expect(storage.accessesOutsideExclusiveAccess == 0)
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
        await #expect(throws: InMemoryAppLockPasswordAttemptStorage.Failure.self) {
            try await sut.countAttempt(stoppingBeforeEraseThreshold: true)
        }
        await #expect(throws: InMemoryAppLockPasswordAttemptStorage.Failure.self) {
            try await sut.hasReachedEraseThreshold()
        }
        await #expect(throws: InMemoryAppLockPasswordAttemptStorage.Failure.self) {
            try await sut.noteRightAttempt()
        }
        await #expect(throws: InMemoryAppLockPasswordAttemptStorage.Failure.self) {
            try await sut.resetCountInARow()
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
        var isExclusive = false
        var accessesOutsideExclusiveAccess = 0
    }

    private let state = Mutex(State())

    /// Reads and writes of the record made without exclusive access, which another process could interleave with.
    var accessesOutsideExclusiveAccess: Int {
        state.withLock(\.accessesOutsideExclusiveAccess)
    }

    func acquireExclusiveAccess() async throws -> AppLockPasswordAttemptAccess {
        state.withLock { $0.isExclusive = true }
        return AppLockPasswordAttemptAccess {
            self.state.withLock { $0.isExclusive = false }
        }
    }

    private func noteAccess() {
        state.withLock { state in
            if !state.isExclusive {
                state.accessesOutsideExclusiveAccess += 1
            }
        }
    }

    var record: AppLockPasswordAttemptRecord? {
        get { state.withLock(\.record) }
        set { state.withLock { $0.record = newValue } }
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
        noteAccess()
        return try state.withLock { state in
            guard !state.failsToLoad else { throw Failure() }
            return state.record
        }
    }

    func save(_ record: AppLockPasswordAttemptRecord) throws {
        noteAccess()
        try state.withLock { state in
            guard !state.failsToSave else { throw Failure() }
            state.record = record
        }
    }

    func remove() {
        noteAccess()
        state.withLock { $0.record = nil }
    }
}
