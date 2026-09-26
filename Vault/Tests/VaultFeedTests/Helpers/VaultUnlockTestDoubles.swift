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

/// The real unlock work, logging each step into a log it can share with the other doubles, and taking the time the
/// test gives each step, on the test's clock and in thread CPU time.
final class SpyUnlockWork: VaultUnlockWork {
    /// How long each step takes.
    struct Timings: Sendable {
        var derivation = Duration.milliseconds(300)
        var keyBox = Duration.milliseconds(1)
        /// Opening a body that opens and decoding its vault.
        var body = Duration.milliseconds(40)
        /// Opening a body that doesn't open, such as the decoy.
        var bodyThatFails = Duration.milliseconds(5)
        /// Time that passes during the derivation with the thread not running, as when the app is suspended. It
        /// passes on the clock, but not in CPU time.
        var suspendedDuringDerivation = Duration.zero
    }

    struct DerivationFailure: Error {}

    private struct State {
        var cpuTime = Duration.zero
        var bodyLengths = [Int]()
        var failsDerivation = false
    }

    private let live = LiveVaultUnlockWork()
    private let log: SharedMutex<[String]>
    private let clock: ManualUnlockClock
    private let timings: Timings
    private let state = SharedMutex(State())
    private let derivationGate = SharedMutex<DispatchSemaphore?>(nil)
    private let isDeriving = SharedMutex(false)

    init(log: SharedMutex<[String]>, clock: ManualUnlockClock, timings: Timings = Timings()) {
        self.log = log
        self.clock = clock
        self.timings = timings
    }

    /// The length of every body opened, in order.
    var bodyLengths: [Int] {
        state.get { $0.bodyLengths }
    }

    func failDerivation() {
        state.modify { $0.failsDerivation = true }
    }

    /// Holds the next derivation until `releaseDerivation()`.
    func holdDerivation() {
        derivationGate.modify { $0 = DispatchSemaphore(value: 0) }
    }

    func releaseDerivation() {
        derivationGate.get { $0 }?.signal()
    }

    /// Waits (for up to 5 seconds) until a derivation is underway.
    func waitUntilDeriving() async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !isDeriving.value, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func threadCPUTime() -> Duration {
        state.get { $0.cpuTime }
    }

    func passwordKey(for password: String, header: VaultSlotFile.Header) throws -> VaultSlotRootKey {
        log.modify { $0.append("derive") }
        isDeriving.modify { $0 = true }
        derivationGate.get { $0 }?.wait()
        spend(timings.derivation)
        clock.advance(by: timings.suspendedDuringDerivation)
        if state.get({ $0.failsDerivation }) {
            throw DerivationFailure()
        }
        return try live.passwordKey(for: password, header: header)
    }

    func openKeyBox(_ index: Int, in file: VaultSlotFile, with key: VaultSlotRootKey) -> VaultSlotFile.OpenedSlot? {
        log.modify { $0.append("try slot \(index)") }
        spend(timings.keyBox)
        return live.openKeyBox(index, in: file, with: key)
    }

    func openBody(of slot: VaultSlotFile.OpenedSlot, in file: VaultSlotFile) throws -> VaultRecordState {
        log.modify { $0.append("open a body") }
        state.modify { $0.bodyLengths.append(slot.bodyLength) }
        do {
            let vault = try live.openBody(of: slot, in: file)
            spend(timings.body)
            return vault
        } catch {
            spend(timings.bodyThatFails)
            throw error
        }
    }

    /// Takes `duration` of CPU time, which passes on the clock too.
    private func spend(_ duration: Duration) {
        state.modify { $0.cpuTime += duration }
        clock.advance(by: duration)
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
    private let whileRemoving = SharedMutex<(@Sendable () -> Void)?>(nil)

    init(log: SharedMutex<[String]>) {
        self.log = log
    }

    /// Runs `action` while the count is being reset, before `remove()` returns.
    func doWhileRemoving(_ action: @escaping @Sendable () -> Void) {
        whileRemoving.modify { $0 = action }
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
        whileRemoving.get { $0 }?()
    }
}

/// A deadline kept in memory.
final class FakeUnlockDeadlineStore: VaultUnlockDeadlineStoring {
    struct RaiseFailure: Error {}

    private let deadline: SharedMutex<Duration>
    private let failsToRaise = SharedMutex(false)

    init(deadline: Duration) {
        self.deadline = SharedMutex(deadline)
    }

    var current: Duration {
        deadline.value
    }

    func failToRaise() {
        failsToRaise.modify { $0 = true }
    }

    func unlockDeadline() async throws -> Duration {
        deadline.value
    }

    func raiseUnlockDeadline(to newDeadline: Duration) async throws {
        if failsToRaise.value {
            throw RaiseFailure()
        }
        deadline.modify { $0 = max($0, newDeadline) }
    }
}
