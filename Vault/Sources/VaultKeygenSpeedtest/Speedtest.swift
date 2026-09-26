// swiftlint:disable all

import ArgumentParser
import CryptoEngine
import Foundation
import FoundationExtensions
import VaultKeygen

// To test this, make sure this is being run in the "release" configuration.
// This is tested by this command: `make benchmark-keygen`

// Latest results (M1 Pro MacBook Pro - Firestorm Core):
//   - Backup Fast = ~0.01s
//   - Backup Secure = ~30s
//   - Item Fast = ~0.01s
//   - Item Secure = ~2s

@main
struct KeygenSpeedtest: ParsableCommand {
    @Flag(
        help: "Calibrate the app lock key derivation for this machine, as the app does on the device, instead of timing the backup and item key derivers.",
    )
    var appLock = false

    func run() throws {
        print("🚧 Build configuration:", buildConfigString())

        if appLock {
            try calibrateAppLock()
        } else {
            try benchmark(keyDeriver: VaultKeyDeriver.Item.Fast.v1, description: "Item Fast")
            try benchmark(keyDeriver: VaultKeyDeriver.Item.Secure.v1, description: "Item Secure")
            try benchmark(keyDeriver: VaultKeyDeriver.Backup.Fast.v1, description: "Backup Fast")
            try benchmark(keyDeriver: VaultKeyDeriver.Backup.Secure.v1, description: "Backup Secure")
        }
    }
}

func benchmark(keyDeriver: some KeyDeriver<KeyData<32>>, description: String) throws {
    print("🚦 Starting '\(description)' derivation")
    let start = Date()
    let key = try keyDeriver.key(password: Data("hello world".utf8), salt: Data("salt".utf8))
    let time = Date().timeIntervalSince(start)
    print("✅ Derived '\(description)' key \(key.data.toHexString()) in \(time)")
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
