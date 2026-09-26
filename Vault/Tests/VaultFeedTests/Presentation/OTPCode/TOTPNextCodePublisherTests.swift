import Combine
import CryptoEngine
import Foundation
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

@MainActor
struct TOTPNextCodePublisherTests {
    /// The RFC 6238 secret's codes either side of 1111111110, the start of a 30-second period.
    private let codeBeforeEdge = "07081804"
    private let codeAfterEdge = "14050471"

    @Test
    func renderedNextCodePublisher_isNilWhileTheWindowIsShut() async throws {
        let (updater, _, sut) = makeSUT(currentTime: 1_111_111_085)

        try await sut.renderedNextCodePublisher().expect(firstValues: [nil]) { @MainActor in
            updater.timerUpdatedPublisherSubject.send(OTPCodeTimerState(
                startTime: 1_111_111_080,
                endTime: 1_111_111_110,
            ))
        }
    }

    @Test
    func renderedNextCodePublisher_isTheCodeOfThePeriodAfterTheOpenOne() async throws {
        let (updater, _, sut) = makeSUT(currentTime: 1_111_111_105)

        try await sut.renderedNextCodePublisher().expect(firstValues: [nil, codeAfterEdge]) { @MainActor in
            updater.timerUpdatedPublisherSubject.send(OTPCodeTimerState(
                startTime: 1_111_111_080,
                endTime: 1_111_111_110,
            ))
        }
    }

    /// Across the edge of a period, the code that showed as next is the one that becomes current, and the next code
    /// goes until the window opens again.
    @Test
    func renderedNextCodePublisher_becomesTheCurrentCodeAtTheEdgeOfThePeriod() async throws {
        let (updater, clock, sut) = makeSUT(currentTime: 1_111_111_109)
        let currentCodes = TOTPCodePublisher(timer: updater, totpGenerator: fixedGenerator()).renderedCodePublisher()
        let before = OTPCodeTimerState(startTime: 1_111_111_080, endTime: 1_111_111_110)
        let after = OTPCodeTimerState(startTime: 1_111_111_110, endTime: 1_111_111_140)

        try await sut.renderedNextCodePublisher().expect(firstValues: [nil, codeAfterEdge, nil]) { @MainActor in
            try await currentCodes.expect(firstValues: [codeBeforeEdge, codeAfterEdge]) { @MainActor in
                updater.timerUpdatedPublisherSubject.send(before)
                clock.currentTime = 1_111_111_110
                updater.timerUpdatedPublisherSubject.send(after)
            }
        }
    }

    // MARK: - Helpers

    private func makeSUT(
        currentTime: Double,
    ) -> (OTPCodeTimerUpdaterMock, EpochClockMock, some OTPNextCodePublisher) {
        let updater = OTPCodeTimerUpdaterMock()
        let clock = EpochClockMock(currentTime: currentTime)
        let window = TOTPNextCodeWindow(timerUpdater: updater, intervalTimer: IntervalTimerMock(), clock: clock)
        let sut = TOTPNextCodePublisher(window: window, totpGenerator: fixedGenerator())
        return (updater, clock, sut)
    }

    private func fixedGenerator() -> TOTPGenerator {
        let hotpGenerator = HOTPGenerator(secret: hotpRfcSecretData(), digits: 8, algorithm: .sha1)
        return TOTPGenerator(generator: hotpGenerator, timeInterval: 30)
    }
}
