import Combine
import Foundation
import VaultCore

/// The last few seconds of each period of a time-based code, when the code after it shows.
///
/// Codes with the same period share one, as they share an `OTPCodeTimerUpdater`: the window follows the updater's
/// periods, opening near the end of each and closing as the next begins.
@MainActor
public final class TOTPNextCodeWindow {
    private let clock: any EpochClock
    private let intervalTimer: any IntervalTimer
    private let openPeriodSubject = CurrentValueSubject<OTPCodeTimerState?, Never>(nil)
    private var openTask: Task<Void, any Error>?
    private var stateCancellable: AnyCancellable?

    public init(timerUpdater: any OTPCodeTimerUpdater, intervalTimer: any IntervalTimer, clock: any EpochClock) {
        self.clock = clock
        self.intervalTimer = intervalTimer
        stateCancellable = timerUpdater.timerUpdatedPublisher
            .sink { [weak self] state in
                self?.follow(state)
            }
    }

    /// The period the window is open in, or `nil` while it's shut.
    public var openPeriodPublisher: AnyPublisher<OTPCodeTimerState?, Never> {
        openPeriodSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Stops the window opening in the current period. It follows the timer updater again once that next publishes.
    public func cancel() {
        openTask?.cancel()
        openTask = nil
    }

    private func follow(_ state: OTPCodeTimerState) {
        cancel()
        let now = clock.currentTime
        if Self.isOpen(in: state, at: now) {
            openPeriodSubject.send(state)
            return
        }
        openPeriodSubject.send(nil)
        let wait = Self.opensAt(in: state) - now
        // Past the end of the period, the updater is about to move on to the next one.
        guard wait > 0 else { return }
        openTask = intervalTimer.schedule(priority: .medium, wait: wait, tolerance: 0.1) { @MainActor [weak self] in
            self?.openPeriodSubject.send(state)
        }
    }
}

extension TOTPNextCodeWindow {
    /// How long before a code expires the next one shows: the last ten seconds, time enough to switch to another app
    /// and enter a code, or the last third of a period too short to spare that, so the current code still shows on
    /// its own for most of its life.
    public static func leadTime(period: Double) -> Double {
        min(10, period / 3)
    }

    /// Whether the next code shows at `time`, in the period `state` describes.
    public static func isOpen(in state: OTPCodeTimerState, at time: Double) -> Bool {
        (opensAt(in: state) ..< state.endTime).contains(time)
    }

    static func opensAt(in state: OTPCodeTimerState) -> Double {
        state.endTime - leadTime(period: state.totalTime)
    }
}
