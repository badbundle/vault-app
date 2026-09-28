import Foundation
import TestHelpers
import Testing
import VaultFeed

struct OTPCodeTimerStateTests {
    @Test
    func init_startTimeAndEndTimeIsValues() {
        let sut = OTPCodeTimerState(startTime: 123, endTime: 456)

        #expect(sut.startTime == 123)
        #expect(sut.endTime == 456)
    }

    @Test
    func init_currentTimePeriod_firstRange() {
        let sut = OTPCodeTimerState(currentTime: 50, period: 30)

        #expect(sut.startTime == 30)
        #expect(sut.endTime == 60)
    }

    @Test
    func init_zeroPeriod_isTreatedAsOneSecond() {
        let sut = OTPCodeTimerState(currentTime: 91.3, period: 0)

        #expect(sut.startTime == 91)
        #expect(sut.endTime == 92)
    }

    @Test
    func init_currentTimePeriod_subsequentRange() {
        let sut = OTPCodeTimerState(currentTime: 91.3, period: 30)

        #expect(sut.startTime == 90)
        #expect(sut.endTime == 120)
    }

    @Test
    func init_currentTimePeriod_isExactRangeBoundary() {
        let sut = OTPCodeTimerState(currentTime: 90, period: 30)

        #expect(sut.startTime == 90)
        #expect(sut.endTime == 120)
    }

    @Test
    func totalTime_isDurationOfTimeRangePositive() {
        let sut = OTPCodeTimerState(startTime: 150, endTime: 250)
        let totalTime = sut.totalTime
        #expect(totalTime.isApproximatelyEqual(to: 100, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func totalTime_isDurationOfTimeRangeNegative() {
        let sut = OTPCodeTimerState(startTime: 250, endTime: 150)
        let totalTime = sut.totalTime
        #expect(totalTime.isApproximatelyEqual(to: -100, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func remainingTime_isTimeRemaining() {
        let sut = OTPCodeTimerState(startTime: 350, endTime: 450)
        let timeRemaining = sut.remainingTime(at: 399)
        #expect(timeRemaining.isApproximatelyEqual(to: 51, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func remainingTime_isTimeRemainingClampsToZero() {
        let sut = OTPCodeTimerState(startTime: 350, endTime: 450)
        let timeRemaining = sut.remainingTime(at: 461)
        #expect(timeRemaining.isApproximatelyEqual(to: 0, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func fractionCompleted_emptyTimeRangeIsCompleted() {
        let sut = OTPCodeTimerState(startTime: 100, endTime: 100)

        #expect(sut.fractionCompleted(at: 100) == 1)
    }

    @Test
    func fractionCompleted_negativeTimeRange() {
        let sut = OTPCodeTimerState(startTime: 100, endTime: 50)

        #expect(sut.fractionCompleted(at: 49) == 0)
        #expect(sut.fractionCompleted(at: 50) == 1)
        #expect(sut.fractionCompleted(at: 75) == 1)
        #expect(sut.fractionCompleted(at: 100) == 1)
        #expect(sut.fractionCompleted(at: 101) == 1)
    }

    @Test
    func fractionCompleted_isFractionOfRangeCompleted() {
        let sut = OTPCodeTimerState(startTime: 350, endTime: 450)
        let fractionCompleted = sut.fractionCompleted(at: 360)
        #expect(fractionCompleted.isApproximatelyEqual(to: 0.1, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func fractionCompleted_isFractionOfRangeCompletedZero() {
        let sut = OTPCodeTimerState(startTime: 350, endTime: 450)
        let fractionCompleted = sut.fractionCompleted(at: 350)
        #expect(fractionCompleted.isApproximatelyEqual(to: 0, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func fractionCompleted_isFractionOfRangeCompletedCapsToZero() {
        let sut = OTPCodeTimerState(startTime: 350, endTime: 450)
        let fractionCompleted = sut.fractionCompleted(at: 340)
        #expect(fractionCompleted.isApproximatelyEqual(to: 0, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func fractionCompleted_isFractionOfRangeCompletedOne() {
        let sut = OTPCodeTimerState(startTime: 350, endTime: 450)
        let fractionCompleted = sut.fractionCompleted(at: 450)
        #expect(fractionCompleted.isApproximatelyEqual(to: 1, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func fractionCompleted_isFractionOfRangeCompletedCapsToOne() {
        let sut = OTPCodeTimerState(startTime: 350, endTime: 450)
        let fractionCompleted = sut.fractionCompleted(at: 460)
        #expect(fractionCompleted.isApproximatelyEqual(to: 1, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func offset_addsTimeToValues() {
        let sut = OTPCodeTimerState(startTime: 100, endTime: 101)

        let offset = sut.offset(time: 23.2)

        #expect(offset.startTime.isApproximatelyEqual(to: 123.2, absoluteTolerance: .ulpOfOne))
        #expect(offset.endTime.isApproximatelyEqual(to: 124.2, absoluteTolerance: .ulpOfOne))
    }

    @Test
    func offset_subtractsTimeFromValues() {
        let sut = OTPCodeTimerState(startTime: 100, endTime: 101)

        let offset = sut.offset(time: -10)

        #expect(offset.startTime.isApproximatelyEqual(to: 90, absoluteTolerance: .ulpOfOne))
        #expect(offset.endTime.isApproximatelyEqual(to: 91, absoluteTolerance: .ulpOfOne))
    }
}
