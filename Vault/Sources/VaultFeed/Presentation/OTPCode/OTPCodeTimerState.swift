import Foundation
import FoundationExtensions

public struct OTPCodeTimerState: Equatable, Sendable {
    /// The number of epoch seconds when the timer started.
    public let startTime: Double
    /// The number of epoch seconds when the timer will end.
    public let endTime: Double

    public init(startTime: Double, endTime: Double) {
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Create a state based on the current time and the repeating period.
    public init(currentTime: Double, period: UInt64) {
        let currentCodeNumber = UInt64(currentTime) / period
        let nextCodeNumber = currentCodeNumber + 1
        startTime = Double(currentCodeNumber * period)
        endTime = Double(nextCodeNumber * period)
    }
}

extension OTPCodeTimerState {
    /// The duration for a full timer rotation.
    public var totalTime: Double {
        endTime - startTime
    }

    /// The amount of time remaining before the timer runs out.
    ///
    /// This won't go below 0.
    public func remainingTime(at epoch: Double) -> Double {
        max(0, endTime - epoch)
    }

    /// The fraction of the timer that has already been completed at the given time.
    ///
    /// This will only give an output `0...1`.
    public func fractionCompleted(at epoch: Double) -> Double {
        if totalTime == 0 {
            return 1
        }
        let remainingTime = remainingTime(at: epoch)
        let remainingFraction = remainingTime / totalTime
        if remainingFraction < 0 {
            return 0
        }
        let fractionCompleted = 1 - remainingFraction
        return fractionCompleted.clamped(to: 0 ... 1)
    }

    public func offset(time offsetTime: Double) -> Self {
        .init(
            startTime: startTime + offsetTime,
            endTime: endTime + offsetTime,
        )
    }
}
