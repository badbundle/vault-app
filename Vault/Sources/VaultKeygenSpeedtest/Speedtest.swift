// swiftlint:disable all

import ArgumentParser
import CryptoEngine
import Foundation
import FoundationExtensions
import VaultKeygen

// To test this, make sure this is being run in the "release" configuration.
// This is tested by this command: `make benchmark-keygen`

// Latest results (M5 Max, the fastest of 3 runs with `--runs 3`, VAULT-128):
//   - Item Fast v1 = ~1 ms
//   - Item Secure v1 = ~140 ms
//   - Backup Fast v1 = ~1 ms
//   - Backup Secure v1 = ~3 s
//   - Argon2id over 64 MiB, 3 passes = ~90 ms with 1 lane, ~30 ms with 4

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
    /// For a derivation that carries on from a stored key, as the app moves a stored backup key to v2: the derivation
    /// that made the stored key. It's derived first, untimed, and only carrying it on is timed.
    var carryingOnFrom: VaultKeyDeriver?

    /// Derives the key `times` times, printing each run, and returns the fastest.
    func run(times: Int) throws -> (description: String, fastest: Duration) {
        print("🚦 Starting '\(description)' derivation")
        let storedKey = try carryingOnFrom?.recreateEncryptionKey(password: "hello world", salt: Data(salt.utf8))
        var fastest: Duration?
        for _ in 0 ..< times {
            let start = ContinuousClock.now
            let key = try derive(carryingOn: storedKey)
            let time = ContinuousClock.now - start
            fastest = min(fastest ?? time, time)
            print("✅ Derived '\(description)' key \(key.data.toHexString()) in \(milliseconds(time))")
        }
        return (description, fastest ?? .zero)
    }

    private func derive(carryingOn storedKey: DerivedEncryptionKey?) throws -> KeyData<32> {
        if let storedKey, let continuing = keyDeriver as? VaultKeyDeriver {
            return try continuing.continueDerivation(from: storedKey).key
        }
        return try keyDeriver.key(password: Data("hello world".utf8), salt: Data(salt.utf8))
    }
}

/// The app's key derivers, then the steps that cost the most on their own, so a change to one shows up.
let benchmarks: [Benchmark] = [
    Benchmark(description: "Item Fast v1", keyDeriver: VaultKeyDeriver.Item.Fast.v1),
    Benchmark(description: "Item Fast v2", keyDeriver: VaultKeyDeriver.Item.Fast.v2, salt: "somesalt"),
    Benchmark(description: "Item Secure v1", keyDeriver: VaultKeyDeriver.Item.Secure.v1),
    Benchmark(description: "Item Secure v2", keyDeriver: VaultKeyDeriver.Item.Secure.v2, salt: "somesalt"),
    Benchmark(description: "Backup Fast v1", keyDeriver: VaultKeyDeriver.Backup.Fast.v1),
    Benchmark(description: "Backup Fast v2", keyDeriver: VaultKeyDeriver.Backup.Fast.v2, salt: "somesalt"),
    Benchmark(
        description: "Backup Fast v1 then v2",
        keyDeriver: VaultKeyDeriver.Backup.Fast.v1ThenV2,
        salt: "somesalt",
    ),
    Benchmark(
        description: "Backup Fast v1 then v2, from a stored v1 key",
        keyDeriver: VaultKeyDeriver.Backup.Fast.v1ThenV2,
        salt: "somesalt",
        carryingOnFrom: VaultKeyDeriver.Backup.Fast.v1,
    ),
    Benchmark(description: "Backup Secure v1", keyDeriver: VaultKeyDeriver.Backup.Secure.v1),
    Benchmark(description: "Backup Secure v2", keyDeriver: VaultKeyDeriver.Backup.Secure.v2, salt: "somesalt"),
    Benchmark(
        description: "Backup Secure v1 then v2 (a restore)",
        keyDeriver: VaultKeyDeriver.Backup.Secure.v1ThenV2,
        salt: "somesalt",
    ),
    Benchmark(
        description: "Backup Secure v1 then v2, from a stored v1 key (the upgrade)",
        keyDeriver: VaultKeyDeriver.Backup.Secure.v1ThenV2,
        salt: "somesalt",
        carryingOnFrom: VaultKeyDeriver.Backup.Secure.v1,
    ),
    Benchmark(
        description: "PBKDF2-SHA384, 372,002 iterations (Item Secure v1's)",
        keyDeriver: PBKDF2KeyDeriver<32>(parameters: .init(iterations: 372_002, variant: .sha384)),
    ),
    Benchmark(
        description: "PBKDF2-SHA384, 5,452,351 iterations (Backup Secure v1's)",
        keyDeriver: PBKDF2KeyDeriver<32>(parameters: .init(iterations: 5_452_351, variant: .sha384)),
    ),
    Benchmark(
        description: "Argon2id, 64 MiB, 3 passes, 1 lane (the App Lock's memory)",
        keyDeriver: Argon2idKeyDeriver<32>(parameters: .init(memoryKiB: 64 * 1024, iterations: 3, parallelism: 1)),
        salt: "somesalt",
    ),
    Benchmark(
        description: "Argon2id, 64 MiB, 3 passes, 4 lanes (the App Lock's memory)",
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

/// Runs the app lock calibration, showing what it measured for each number of lanes and which it chose, then times
/// a derivation with the parameters it chose.
func calibrateAppLock() throws {
    print("🚦 Calibrating the app lock key derivation")
    let start = ContinuousClock.now
    let measurements = try AppLockKeyDerivationCalibrator().measureLanes()
    let calibrationTime = ContinuousClock.now - start
    for measurement in measurements {
        let lanes = measurement.lanes == 1 ? "1 lane: " : "\(measurement.lanes) lanes:"
        print(
            "   \(lanes) \(milliseconds(measurement.timePerPass)) a pass, so \(measurement.passes) passes",
            "in \(milliseconds(measurement.expectedDuration))",
        )
    }
    let calibration = AppLockKeyDerivationCalibrator.calibration(choosingFrom: measurements)
    let parameters = calibration.parameters
    let lanes = parameters.parallelism == 1 ? "1 lane" : "\(parameters.parallelism) lanes"
    print("✅ Chose \(lanes) and \(parameters.iterations) passes over \(parameters.memoryKiB / 1024) MiB")
    print("   Calibrating took \(milliseconds(calibrationTime))")
    print("   Expected derivation: \(milliseconds(calibration.expectedDerivationDuration))")
    print("   Unlock deadline: \(milliseconds(calibration.unlockDeadline))")
    let actual = try Argon2idDerivationTimer().timeDerivation(parameters: parameters)
    print("   One derivation with these parameters took \(milliseconds(actual))")
}

func buildConfigString() -> String {
    #if DEBUG
    return "⚠️ DEBUG"
    #else
    return "✅ RELEASE"
    #endif
}
