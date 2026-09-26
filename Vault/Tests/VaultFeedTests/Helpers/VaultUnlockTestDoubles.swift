import Foundation
import FoundationExtensions
@testable import VaultFeed

/// Time that moves only when the test says so, or when unlocking waits for its deadline.
final class ManualUnlockClock: VaultUnlockClock {
    private struct State {
        var now = ContinuousClock.now
        var sleeps = [ContinuousClock.Instant]()
        var isHolding = false
        var held = [CheckedContinuation<Void, Never>]()
    }

    private let state = SharedMutex(State())

    var now: ContinuousClock.Instant {
        state.get { $0.now }
    }

    /// Every instant something waited until, in order.
    var sleeps: [ContinuousClock.Instant] {
        state.get { $0.sleeps }
    }

    func advance(by duration: Duration) {
        state.modify { $0.now = $0.now.advanced(by: duration) }
    }

    /// Waits are held from now on, until `release()`.
    func hold() {
        state.modify { $0.isHolding = true }
    }

    func release() {
        let held = state.modify { state in
            state.isHolding = false
            defer { state.held.removeAll() }
            return state.held
        }
        for continuation in held {
            continuation.resume()
        }
    }

    /// Waits (for up to 5 seconds) until something is waiting on a held deadline.
    func waitUntilHolding() async {
        let deadline = ContinuousClock.now + .seconds(5)
        while state.get({ $0.held.isEmpty }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        await withCheckedContinuation { continuation in
            state.modify { state in
                state.sleeps.append(deadline)
                if state.isHolding {
                    state.held.append(continuation)
                } else {
                    continuation.resume()
                }
            }
        }
        state.modify { $0.now = max($0.now, deadline) }
    }
}

/// The real unlock work, logging each step into a log it can share with the other doubles.
///
/// Deriving the key can take as long as the test says, on the test's clock.
final class SpyUnlockWork: VaultUnlockWork {
    private let live = LiveVaultUnlockWork()
    private let log: SharedMutex<[String]>
    private let clock: ManualUnlockClock
    private let derivationDuration: Duration

    init(log: SharedMutex<[String]>, clock: ManualUnlockClock, derivationDuration: Duration = .zero) {
        self.log = log
        self.clock = clock
        self.derivationDuration = derivationDuration
    }

    func passwordKey(for password: Data, header: VaultSlotFile.Header) throws -> VaultSlotRootKey {
        log.modify { $0.append("derive") }
        clock.advance(by: derivationDuration)
        return try live.passwordKey(for: password, header: header)
    }

    func openKeyBox(_ index: Int, in file: VaultSlotFile, with key: VaultSlotRootKey) -> VaultSlotFile.OpenedSlot? {
        log.modify { $0.append("try slot \(index)") }
        return live.openKeyBox(index, in: file, with: key)
    }

    func openBody(of slot: VaultSlotFile.OpenedSlot, in file: VaultSlotFile) throws -> VaultRecordState {
        log.modify { $0.append("open a body") }
        return try live.openBody(of: slot, in: file)
    }
}

/// Where `AppLockPasswordAttemptCounter` keeps its count, in memory: logging into a shared log, and failing when the
/// test says.
///
/// Counting an attempt saves a record, and resetting the count removes it.
final class LoggingAttemptStorage: AppLockPasswordAttemptStorage {
    struct Failure: Error {}

    private struct State {
        var record: AppLockPasswordAttemptRecord?
        var failsToSave = false
        var failsToRemove = false
    }

    private let log: SharedMutex<[String]>
    private let state = SharedMutex(State())

    init(log: SharedMutex<[String]>) {
        self.log = log
    }

    /// Makes the counter find `count` wrong attempts in a row, the latest at `latestAt`.
    func setRecord(count: Int, latestAt: ContinuousClock.Instant) {
        state.modify { $0.record = AppLockPasswordAttemptRecord(count: count, latestAt: latestAt) }
    }

    func failToSave() {
        state.modify { $0.failsToSave = true }
    }

    func failToRemove() {
        state.modify { $0.failsToRemove = true }
    }

    func load() throws -> AppLockPasswordAttemptRecord? {
        state.get { $0.record }
    }

    func save(_ record: AppLockPasswordAttemptRecord) throws {
        try state.modify { state in
            guard !state.failsToSave else { throw Failure() }
            state.record = record
        }
        log.modify { $0.append("count the attempt") }
    }

    func remove() throws {
        try state.modify { state in
            guard !state.failsToRemove else { throw Failure() }
            state.record = nil
        }
        log.modify { $0.append("reset the count") }
    }
}

/// A deadline kept in memory.
final class FakeUnlockDeadlineStore: VaultUnlockDeadlineStoring {
    private let deadline: SharedMutex<Duration>

    init(deadline: Duration) {
        self.deadline = SharedMutex(deadline)
    }

    var current: Duration {
        deadline.value
    }

    func unlockDeadline() async throws -> Duration {
        deadline.value
    }

    func raiseUnlockDeadline(to newDeadline: Duration) async throws {
        deadline.modify { $0 = max($0, newDeadline) }
    }
}
