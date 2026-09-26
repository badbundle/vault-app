import Combine
import Foundation
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

@MainActor
struct TOTPNextCodeWindowTests {
    @Test(arguments: [
        (30.0, 10.0),
        (60, 10),
        (90, 10),
        (15, 5),
        (6, 2),
    ])
    func leadTime_isTenSecondsOrAThirdOfAShortPeriod(period: Double, expected: Double) {
        #expect(TOTPNextCodeWindow.leadTime(period: period) == expected)
    }

    @Test(arguments: [
        (100.0, false),
        (119.9, false),
        (120, true),
        (125, true),
        (129.99, true),
        (130, false),
        (99, false),
    ])
    func isOpen_duringTheLastTenSecondsOfAThirtySecondPeriod(time: Double, expected: Bool) {
        let state = OTPCodeTimerState(startTime: 100, endTime: 130)

        #expect(TOTPNextCodeWindow.isOpen(in: state, at: time) == expected)
    }

    @Test(arguments: [
        (104.9, false),
        (105, true),
        (109.9, true),
    ])
    func isOpen_duringTheLastThirdOfAShortPeriod(time: Double, expected: Bool) {
        let state = OTPCodeTimerState(startTime: 95, endTime: 110)

        #expect(TOTPNextCodeWindow.isOpen(in: state, at: time) == expected)
    }

    @Test(arguments: [
        (OTPCodeTimerState(startTime: 100, endTime: 130), 120),
        (OTPCodeTimerState(startTime: 120, endTime: 180), 170),
        (OTPCodeTimerState(startTime: 90, endTime: 105), 100),
    ] as [(OTPCodeTimerState, Double)])
    func opensAt_isTheLeadTimeBeforeThePeriodEnds(state: OTPCodeTimerState, expected: Double) {
        #expect(TOTPNextCodeWindow.opensAt(in: state) == expected)
    }

    @Test
    func openPeriodPublisher_isShutBeforeAnyPeriod() async throws {
        let (_, _, _, sut) = makeSUT(currentTime: 125)

        try await sut.openPeriodPublisher.expect(firstValues: [nil]) {}
    }

    @Test
    func openPeriodPublisher_opensAtOnceWhenAPeriodStartsInsideTheWindow() async throws {
        let (updater, _, _, sut) = makeSUT(currentTime: 125)
        let state = OTPCodeTimerState(startTime: 100, endTime: 130)

        try await sut.openPeriodPublisher.expect(firstValues: [nil, state]) { @MainActor in
            updater.timerUpdatedPublisherSubject.send(state)
        }
    }

    @Test
    func openPeriodPublisher_opensWhenTheWindowStarts() async throws {
        let (updater, timer, _, sut) = makeSUT(currentTime: 105)
        let state = OTPCodeTimerState(startTime: 100, endTime: 130)

        try await sut.openPeriodPublisher.expect(firstValues: [nil, state]) { @MainActor in
            updater.timerUpdatedPublisherSubject.send(state)
            try await timer.finishTimer()
        }
    }

    @Test
    func openPeriodPublisher_shutsWhenTheNextPeriodStarts() async throws {
        let (updater, _, clock, sut) = makeSUT(currentTime: 125)
        let first = OTPCodeTimerState(startTime: 100, endTime: 130)
        let second = OTPCodeTimerState(startTime: 130, endTime: 160)

        try await sut.openPeriodPublisher.expect(firstValues: [nil, first, nil]) { @MainActor in
            updater.timerUpdatedPublisherSubject.send(first)
            clock.currentTime = 130
            updater.timerUpdatedPublisherSubject.send(second)
        }
    }

    /// The updater is about to move on to the next period.
    @Test
    func openPeriodPublisher_staysShutWhenThePeriodHasAlreadyEnded() async throws {
        let (updater, _, _, sut) = makeSUT(currentTime: 131)

        try await sut.openPeriodPublisher.expect(firstValues: [nil]) { @MainActor in
            updater.timerUpdatedPublisherSubject.send(OTPCodeTimerState(startTime: 100, endTime: 130))
        }
    }
}

// MARK: - Helpers

extension TOTPNextCodeWindowTests {
    private func makeSUT(
        currentTime: Double,
    ) -> (OTPCodeTimerUpdaterMock, IntervalTimerMock, EpochClockMock, TOTPNextCodeWindow) {
        let updater = OTPCodeTimerUpdaterMock()
        let timer = IntervalTimerMock()
        let clock = EpochClockMock(currentTime: currentTime)
        let sut = TOTPNextCodeWindow(timerUpdater: updater, intervalTimer: timer, clock: clock)
        return (updater, timer, clock, sut)
    }
}
