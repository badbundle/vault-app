// swiftlint:disable all

import ArgumentParser
import CryptoEngine
import Foundation
import FoundationExtensions
import VaultKeygen

// To test this, make sure this is being run in the "release" configuration.
// This is tested by this command: `make benchmark-keygen`

// Latest results (M5 Max, the fastest of 3 runs with `--runs 3`):
//   - Item Fast v1 = ~3 ms
//   - Item Secure v1 = ~1 s
//   - Backup Fast v1 = ~6 ms
//   - Backup Secure v1 = ~15 s
//   - Argon2id over 64 MiB, 3 passes = ~100 ms, with 1 lane or 4

@main
struct KeygenSpeedtest: ParsableCommand {
    @Flag(
        help: "Calibrate the app lock key derivation for this machine, as the app does on the device, instead of timing the backup and item key derivers.",
    )
    var appLock = false

    @Option(
        help: "How many times to run each derivation. The fastest run is reported, so a moment when the machine is busy doesn't count against it.",
    )
    var runs = 1

    func run() throws {
        print("🚧 Build configuration:", buildConfigString())

        if appLock {
            try calibrateAppLock()
        } else {
            let runs = max(runs, 1)
            let results = try benchmarks.map { try $0.run(times: runs) }
            printSummary(results, runs: runs)
        }
    }
}

/// A key derivation to time, and what to call it.
struct Benchmark {
    var description: String
    var keyDeriver: any KeyDeriver<KeyData<32>>
    /// The salt to derive with. Argon2id needs at least 8 bytes, so its rows use a longer one.
    var salt = "salt"

    /// Derives the key `times` times, printing each run, and returns the fastest.
    func run(times: Int) throws -> (description: String, fastest: Duration) {
        print("🚦 Starting '\(description)' derivation")
        var fastest: Duration?
        for _ in 0 ..< times {
            let start = ContinuousClock.now
            let key = try keyDeriver.key(password: Data("hello world".utf8), salt: Data(salt.utf8))
            let time = ContinuousClock.now - start
            fastest = min(fastest ?? time, time)
            print("✅ Derived '\(description)' key \(key.data.toHexString()) in \(milliseconds(time))")
        }
        return (description, fastest ?? .zero)
    }
}

/// The app's key derivers, then the steps that cost the most on their own, so a change to one shows up.
let benchmarks: [Benchmark] = [
    Benchmark(description: "Item Fast v1", keyDeriver: VaultKeyDeriver.Item.Fast.v1),
    Benchmark(description: "Item Secure v1", keyDeriver: VaultKeyDeriver.Item.Secure.v1),
    Benchmark(description: "Backup Fast v1", keyDeriver: VaultKeyDeriver.Backup.Fast.v1),
    Benchmark(description: "Backup Secure v1", keyDeriver: VaultKeyDeriver.Backup.Secure.v1),
    Benchmark(
        description: "PBKDF2-SHA384, 372,002 iterations (Item Secure v1's)",
        keyDeriver: PBKDF2KeyDeriver<32>(parameters: .init(iterations: 372_002, variant: .sha384)),
    ),
    Benchmark(
        description: "PBKDF2-SHA384, 5,452,351 iterations (Backup Secure v1's)",
        keyDeriver: PBKDF2KeyDeriver<32>(parameters: .init(iterations: 5_452_351, variant: .sha384)),
    ),
    Benchmark(
        description: "Argon2id, 64 MiB, 3 passes, 1 lane (the App Lock's)",
        keyDeriver: Argon2idKeyDeriver<32>(parameters: .init(memoryKiB: 64 * 1024, iterations: 3, parallelism: 1)),
        salt: "somesalt",
    ),
    Benchmark(
        description: "Argon2id, 64 MiB, 3 passes, 4 lanes",
        keyDeriver: Argon2idKeyDeriver<32>(parameters: .init(memoryKiB: 64 * 1024, iterations: 3, parallelism: 4)),
        salt: "somesalt",
    ),
]

/// Prints the fastest time for each derivation, lined up.
func printSummary(_ results: [(description: String, fastest: Duration)], runs: Int) {
    let width = results.map(\.description.count).max() ?? 0
    print("")
    print(runs == 1 ? "⏱️ Timings:" : "⏱️ Fastest of \(runs) runs:")
    for result in results {
        let padding = String(repeating: " ", count: width - result.description.count)
        print("   \(result.description)\(padding)  \(milliseconds(result.fastest))")
    }
}

/// The duration in milliseconds, to a tenth.
func milliseconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    let milliseconds = Double(seconds) * 1000 + Double(attoseconds) / 1e15
    return String(format: "%.1f ms", milliseconds)
}

/// Runs the app lock calibration, then times a derivation with the parameters it chose.
func calibrateAppLock() throws {
    print("🚦 Calibrating the app lock key derivation")
    let calibration = try AppLockKeyDerivationCalibrator().calibrate()
    let parameters = calibration.parameters
    print("✅ Chose \(parameters.iterations) passes over \(parameters.memoryKiB / 1024) MiB")
    print("   Expected derivation: \(calibration.expectedDerivationDuration)")
    print("   Unlock deadline: \(calibration.unlockDeadline)")
    let actual = try Argon2idDerivationTimer().timeDerivation(parameters: parameters)
    print("   One derivation with these parameters took \(actual)")
}

func buildConfigString() -> String {
    #if DEBUG
    return "⚠️ DEBUG"
    #else
    return "✅ RELEASE"
    #endif
}
