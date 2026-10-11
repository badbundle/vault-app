import CryptoEngine
import Foundation
import Testing
@testable import VaultFeed

struct LiveVaultUnlockWorkTests {
    private let sut = LiveVaultUnlockWork()

    /// Four lanes run on threads of their own while the calling thread waits, so its own CPU time would miss nearly
    /// all of their work, and the unlock deadline would never be raised for a slower device.
    @Test
    func cpuTime_ofADerivationWithFourLanes_countsTheirShareOfTheWork() throws {
        let oneLane = try cpuTimeOfDerivation(lanes: 1)
        let fourLanes = try cpuTimeOfDerivation(lanes: 4)

        // Four lanes share one lane's work between them, so each does about a quarter of it. Only a lower bound is
        // checked: the share also counts any other thread of the process that ran meanwhile, such as other tests'.
        #expect(fourLanes > oneLane / 8)
    }

    /// The CPU time the work counts for one derivation over 64 MiB with `lanes` lanes.
    private func cpuTimeOfDerivation(lanes: UInt32) throws -> Duration {
        let header = try VaultSlotFile.Header(
            slotSize: VaultSlotFile.minimumSlotSize,
            kdfParameters: Argon2idParameters(memoryKiB: 64 * 1024, iterations: 3, parallelism: lanes),
            salt: Data(repeating: 1, count: VaultSlotFile.Header.saltLength),
        )
        let start = sut.cpuTime(lanes: lanes)
        _ = try sut.passwordKey(for: "correct horse", header: header)
        return sut.cpuTime(lanes: lanes) - start
    }
}
