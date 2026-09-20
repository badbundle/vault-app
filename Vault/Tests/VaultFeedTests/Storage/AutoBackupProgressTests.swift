import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

struct AutoBackupProgressTests {
    @Test
    func fractionCompleted_isZeroAtStart() {
        #expect(AutoBackupProgress.starting.fractionCompleted == 0)
    }

    @Test
    func fractionCompleted_isOneWhenSavingFinishes() {
        let sut = AutoBackupProgress(phase: .saving, phaseFraction: 1)

        #expect(sut.fractionCompleted == 1)
    }

    @Test
    func fractionCompleted_mapsPhaseFractionIntoPhaseRange() {
        let start = AutoBackupProgress(phase: .rendering, phaseFraction: 0)
        let half = AutoBackupProgress(phase: .rendering, phaseFraction: 0.5)
        let end = AutoBackupProgress(phase: .rendering, phaseFraction: 1)

        #expect(start.fractionCompleted < half.fractionCompleted)
        #expect(half.fractionCompleted < end.fractionCompleted)
        #expect(half.fractionCompleted.isApproximatelyEqual(
            to: (start.fractionCompleted + end.fractionCompleted) / 2,
            absoluteTolerance: 1e-9,
        ))
    }

    @Test
    func fractionCompleted_isContinuousAcrossPhaseBoundaries() {
        let phases = AutoBackupProgress.Phase.allCases
        for (phase, next) in zip(phases, phases.dropFirst()) {
            let endOfPhase = AutoBackupProgress(phase: phase, phaseFraction: 1)
            let startOfNext = AutoBackupProgress(phase: next, phaseFraction: 0)
            #expect(
                endOfPhase.fractionCompleted.isApproximatelyEqual(
                    to: startOfNext.fractionCompleted,
                    absoluteTolerance: 1e-9,
                ),
                "\(phase) -> \(next)",
            )
        }
    }

    @Test
    func fractionCompleted_neverDecreasesAcrossPhases() {
        let phases = AutoBackupProgress.Phase.allCases
        for (phase, next) in zip(phases, phases.dropFirst()) {
            let startOfPhase = AutoBackupProgress(phase: phase, phaseFraction: 0)
            let startOfNext = AutoBackupProgress(phase: next, phaseFraction: 0)
            #expect(startOfPhase.fractionCompleted < startOfNext.fractionCompleted, "\(phase) -> \(next)")
        }
    }

    @Test
    func init_clampsPhaseFraction() {
        #expect(AutoBackupProgress(phase: .rendering, phaseFraction: -0.5).phaseFraction == 0)
        #expect(AutoBackupProgress(phase: .rendering, phaseFraction: 1.5).phaseFraction == 1)
    }
}
