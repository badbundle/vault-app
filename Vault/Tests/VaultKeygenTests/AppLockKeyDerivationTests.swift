import Foundation
import FoundationExtensions
import Testing
@testable import VaultKeygen

struct AppLockKeyDerivationTests {
    @Test
    func calibrate_timesThreeRunsOfThreePassesOver64MiB_takingTurnsBetweenOneTwoAndFourLanes() throws {
        let timer = ScriptedTimer(eachRun: [1: .milliseconds(150), 2: .milliseconds(90), 4: .milliseconds(60)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        _ = try sut.calibrate()

        let turn = [1, 2, 4].map { Argon2idParameters(memoryKiB: 65536, iterations: 3, parallelism: $0) }
        #expect(timer.requestedParameters == turn + turn + turn)
    }

    @Test
    func measureLanes_usesTheFastestRunForEachNumberOfLanes() throws {
        let timer = ScriptedTimer(runs: [
            1: [.milliseconds(300), .milliseconds(150), .milliseconds(240)],
            2: [.milliseconds(90), .milliseconds(120), .milliseconds(96)],
            4: [.milliseconds(75), .milliseconds(80), .milliseconds(60)],
        ])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let measurements = try sut.measureLanes()

        #expect(measurements == [
            .init(lanes: 1, timePerPass: .milliseconds(50)),
            .init(lanes: 2, timePerPass: .milliseconds(30)),
            .init(lanes: 4, timePerPass: .milliseconds(20)),
        ])
        #expect(measurements.map(\.passes) == [20, 33, 50])
        #expect(measurements.map(\.expectedDuration) == [.milliseconds(1000), .milliseconds(990), .milliseconds(1000)])
    }

    /// For example, a device without four cores to run four lanes side by side.
    @Test
    func calibrate_choosesTheLanesThatFitTheMostPasses() throws {
        // 60, 30 and 40 ms a pass: 16, 33 and 25 passes fit in a second.
        let timer = ScriptedTimer(eachRun: [1: .milliseconds(180), 2: .milliseconds(90), 4: .milliseconds(120)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration == AppLockKeyDerivationCalibration(
            parameters: Argon2idParameters(memoryKiB: 65536, iterations: 33, parallelism: 2),
            expectedDerivationDuration: .milliseconds(990),
            unlockDeadline: .milliseconds(1485),
        ))
    }

    @Test
    func calibrate_lanesThatFitTheCeilingEach_choosesTheQuickest() throws {
        // 6, 3 and 2 ms a pass: 166, 333 and 500 passes fit, so each gets the ceiling of 128.
        let timer = ScriptedTimer(eachRun: [1: .milliseconds(18), 2: .milliseconds(9), 4: .milliseconds(6)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters == Argon2idParameters(memoryKiB: 65536, iterations: 128, parallelism: 4))
        #expect(calibration.expectedDerivationDuration == .milliseconds(256))
        #expect(calibration.unlockDeadline == .milliseconds(384))
    }

    @Test
    func calibrate_lanesThatFitOnlyTheFloorEach_chooseTheQuickest() throws {
        // 900, 600 and 500 ms a pass: 1, 1 and 2 passes fit, so each gets the floor of 3.
        let timer = ScriptedTimer(eachRun: [1: .milliseconds(2700), 2: .milliseconds(1800), 4: .milliseconds(1500)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters == Argon2idParameters(memoryKiB: 65536, iterations: 3, parallelism: 4))
        #expect(calibration.expectedDerivationDuration == .milliseconds(1500))
        #expect(calibration.unlockDeadline == .milliseconds(2250))
    }

    @Test
    func calibrate_moreLanesThatAreNoQuicker_keepsTheFewest() throws {
        let timer = ScriptedTimer(eachRun: [1: .milliseconds(150), 2: .milliseconds(150), 4: .milliseconds(150)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters == Argon2idParameters(memoryKiB: 65536, iterations: 20, parallelism: 1))
    }

    @Test
    func calibrate_roundsPassesDown() throws {
        // 60 ms a pass with one lane: 16.67 passes fit, so 16. More lanes are slower here.
        let timer = ScriptedTimer(eachRun: [1: .milliseconds(180), 2: .milliseconds(200), 4: .milliseconds(240)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration == AppLockKeyDerivationCalibration(
            parameters: Argon2idParameters(memoryKiB: 65536, iterations: 16, parallelism: 1),
            expectedDerivationDuration: .milliseconds(960),
            unlockDeadline: .milliseconds(1440),
        ))
    }

    @Test
    func calibrate_neverChoosesFewerThanThreePasses() throws {
        // 500 ms a pass on a slow device, with any lanes: only 2 passes fit, but the floor is 3.
        let timer = ScriptedTimer(eachRun: [1: .milliseconds(1500), 2: .milliseconds(1500), 4: .milliseconds(1500)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters.iterations == 3)
        #expect(calibration.expectedDerivationDuration == .milliseconds(1500))
        #expect(calibration.unlockDeadline == .milliseconds(2250))
    }

    @Test
    func calibrate_neverChoosesMoreThan128Passes() throws {
        // 1 ms a pass on a very fast device, with any lanes: 1,000 passes fit, but the ceiling is 128.
        let timer = ScriptedTimer(eachRun: [1: .milliseconds(3), 2: .milliseconds(3), 4: .milliseconds(3)])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters.iterations == 128)
        #expect(calibration.expectedDerivationDuration == .milliseconds(128))
        #expect(calibration.unlockDeadline == .milliseconds(192))
    }

    @Test
    func calibrate_choosesTheCeilingForAZeroDuration() throws {
        let timer = ScriptedTimer(runs: [
            1: [.zero, .milliseconds(150), .milliseconds(150)],
            2: Array(repeating: .milliseconds(150), count: 3),
            4: Array(repeating: .milliseconds(150), count: 3),
        ])
        let sut = AppLockKeyDerivationCalibrator(timer: timer)

        let calibration = try sut.calibrate()

        #expect(calibration.parameters == Argon2idParameters(memoryKiB: 65536, iterations: 128, parallelism: 1))
        #expect(calibration.expectedDerivationDuration == .zero)
    }

    @Test
    func passes_fitExactlyTheBoundaryPasses() {
        // 10 ms a pass fits exactly 100.
        #expect(AppLockKeyDerivationCalibrator.passes(timePerPass: .milliseconds(10)) == 100)
        // 1,000 / 3 ms a pass fits exactly 3, the floor.
        #expect(AppLockKeyDerivationCalibrator.passes(timePerPass: .seconds(1) / 3) == 3)
        // 1,000 / 128 ms a pass fits exactly 128, the ceiling.
        #expect(AppLockKeyDerivationCalibrator.passes(timePerPass: .seconds(1) / 128) == 128)
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
        #expect(AppLockKeyDerivation.passesRange == 3 ... 128)
        #expect(AppLockKeyDerivation.laneCounts == [1, 2, 4])
        #expect(AppLockKeyDerivation.targetDuration == .seconds(1))
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

/// Returns the given durations for each number of lanes in turn, and records the parameters it's asked to time.
private struct ScriptedTimer: Argon2idDerivationTiming {
    private let state: SharedMutex<(runs: [UInt32: [Duration]], requested: [Argon2idParameters])>

    init(runs: [UInt32: [Duration]]) {
        state = SharedMutex((runs: runs, requested: []))
    }

    /// Every run with a number of lanes takes the same time.
    init(eachRun: [UInt32: Duration]) {
        self.init(runs: eachRun.mapValues { Array(repeating: $0, count: AppLockKeyDerivation.calibrationRuns) })
    }

    var requestedParameters: [Argon2idParameters] {
        state.get(\.requested)
    }

    func timeDerivation(parameters: Argon2idParameters) throws -> Duration {
        state.modify { state in
            state.requested.append(parameters)
            return state.runs[parameters.parallelism, default: []].removeFirst()
        }
    }
}

private struct FailingTimer: Argon2idDerivationTiming {
    struct Failure: Error {}

    func timeDerivation(parameters _: Argon2idParameters) throws -> Duration {
        throw Failure()
    }
}
