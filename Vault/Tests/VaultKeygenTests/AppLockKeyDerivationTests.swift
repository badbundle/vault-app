import Foundation
import FoundationExtensions
import Testing
@testable import VaultKeygen

struct AppLockKeyDerivationTests {
    @Test
    func calibrate_timesThreeRunsOfThreePassesOver64MiB() throws {
        let timer = ScriptedTimer(durations: [.milliseconds(150), .milliseconds(150), .milliseconds(150)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        _ = try sut.calibrate()

        let expected = Argon2idParameters(memoryKiB: 65536, iterations: 3, parallelism: 1)
        #expect(timer.requestedParameters == [expected, expected, expected])
    }

    @Test
    func calibrate_usesTheFastestRun() throws {
        // 150 ms for 3 passes is 50 ms a pass, so 10 passes fit in 500 ms.
        let timer = ScriptedTimer(durations: [.milliseconds(300), .milliseconds(150), .milliseconds(240)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration == AppLockKeyDerivationCalibration(
            parameters: Argon2idParameters(memoryKiB: 65536, iterations: 10, parallelism: 1),
            expectedDerivationDuration: .milliseconds(500),
            unlockDeadline: .milliseconds(750),
        ))
    }

    @Test
    func calibrate_roundsPassesDown() throws {
        // 60 ms a pass: 8.33 passes fit, so 8.
        let timer = ScriptedTimer(durations: Array(repeating: .milliseconds(180), count: 3))
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters.iterations == 8)
        #expect(calibration.expectedDerivationDuration == .milliseconds(480))
        #expect(calibration.unlockDeadline == .milliseconds(720))
    }

    @Test
    func calibrate_neverChoosesFewerThanThreePasses() throws {
        // 300 ms a pass on a slow device: only 1 pass fits, but the floor is 3.
        let timer = ScriptedTimer(durations: Array(repeating: .milliseconds(900), count: 3))
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters.iterations == 3)
        #expect(calibration.expectedDerivationDuration == .milliseconds(900))
        #expect(calibration.unlockDeadline == .milliseconds(1350))
    }

    @Test
    func calibrate_neverChoosesMoreThan32Passes() throws {
        // 1 ms a pass on a very fast device: 500 passes fit, but the ceiling is 32.
        let timer = ScriptedTimer(durations: Array(repeating: .milliseconds(3), count: 3))
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters.iterations == 32)
        #expect(calibration.expectedDerivationDuration == .milliseconds(32))
        #expect(calibration.unlockDeadline == .milliseconds(48))
    }

    @Test
    func calibrate_choosesTheCeilingForAZeroDuration() throws {
        let timer = ScriptedTimer(durations: [.zero, .milliseconds(150), .milliseconds(150)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters.iterations == 32)
        #expect(calibration.expectedDerivationDuration == .zero)
    }

    @Test
    func calibrate_choosesExactlyTheBoundaryPasses() throws {
        // 50 ms a pass fits exactly 10.
        #expect(AppLockKeyDerivationCalibrator.passes(timePerPass: .milliseconds(50)) == 10)
        // 500 / 3 ms a pass fits exactly 3, the floor.
        #expect(AppLockKeyDerivationCalibrator.passes(timePerPass: .milliseconds(500) / 3) == 3)
        // 500 / 32 ms a pass fits exactly 32, the ceiling.
        #expect(AppLockKeyDerivationCalibrator.passes(timePerPass: .milliseconds(500) / 32) == 32)
    }

    @Test
    func calibrate_throwsWhenADerivationFails() {
        let sut = AppLockKeyDerivationCalibrator(timer: FailingTimer())

        #expect(throws: FailingTimer.Failure.self) {
            try sut.calibrate()
        }
    }

    @Test
    func constants_matchTheDesign() {
        #expect(AppLockKeyDerivation.memoryKiB == 64 * 1024)
        #expect(AppLockKeyDerivation.passesRange == 3 ... 32)
        #expect(AppLockKeyDerivation.targetDuration == .milliseconds(500))
        #expect(AppLockKeyDerivation.deadlineMultiplier == 1.5)
        #expect(AppLockKeyDerivation.calibrationRuns == 3)
        #expect(AppLockKeyDerivation.calibrationPasses == 3)
    }

    @Test
    func keyDeriver_usesTheGivenParameters() {
        let parameters = Argon2idParameters(memoryKiB: 65536, iterations: 12, parallelism: 1)

        let deriver = AppLockKeyDerivation.keyDeriver(parameters: parameters)

        #expect(deriver.parameters == parameters)
        #expect(
            deriver.uniqueAlgorithmIdentifier ==
                "ARGON2ID<keyLength=32;memoryKiB=65536;iterations=12;parallelism=1;version=19>",
        )
    }

    @Test
    func derivationTimer_timesARealDerivation() throws {
        let sut = Argon2idDerivationTimer()

        let duration = try sut.timeDerivation(parameters: .init(memoryKiB: 64, iterations: 1, parallelism: 1))

        #expect(duration > .zero)
    }
}

// MARK: - Helpers

/// Returns the given durations in order and records the parameters it's asked to time.
private struct ScriptedTimer: Argon2idDerivationTiming {
    private let state: SharedMutex<(durations: [Duration], requested: [Argon2idParameters])>

    init(durations: [Duration]) {
        state = SharedMutex((durations: durations, requested: []))
    }

    var requestedParameters: [Argon2idParameters] {
        state.get(\.requested)
    }

    func timeDerivation(parameters: Argon2idParameters) throws -> Duration {
        state.modify { state in
            state.requested.append(parameters)
            return state.durations.removeFirst()
        }
    }
}

private struct FailingTimer: Argon2idDerivationTiming {
    struct Failure: Error {}

    func timeDerivation(parameters _: Argon2idParameters) throws -> Duration {
        throw Failure()
    }
}
