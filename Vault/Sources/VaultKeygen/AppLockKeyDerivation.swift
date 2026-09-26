import CryptoEngine
import Foundation
import FoundationExtensions

/// How the app lock password derives its key: Argon2id over 64 MiB, with the number of passes calibrated on the
/// device that creates the encrypted vault (see `docs/on-device-encryption.md`, "Key derivation").
///
/// The parameters are chosen once, when the encrypted file is created, and stored in its header. Every vault in the
/// file derives with them from then on, so they can't be tuned per vault or raised later.
public enum AppLockKeyDerivation {
    /// The memory every derivation uses: 64 MiB, which the AutoFill extension can spare.
    public static let memoryKiB: UInt32 = 64 * 1024
    /// The passes calibration can choose. The floor is RFC 9106's recommended 3 passes at 64 MiB. The ceiling keeps
    /// unlocking bounded if a very fast device calibrates and the file is later restored to a slower one.
    public static let passesRange: ClosedRange<UInt32> = 3 ... 32
    /// How long calibration aims for one derivation to take.
    public static let targetDuration: Duration = .milliseconds(500)
    /// The unlock deadline, as a multiple of the expected derivation time. The rest is time to try the vault slots
    /// and decode the vault.
    public static let deadlineMultiplier = 1.5
    /// The number of timed derivations calibration makes. It uses the fastest, so a moment when the device is busy
    /// can't make it choose too few passes.
    public static let calibrationRuns = 3
    /// The passes each timed derivation makes.
    public static let calibrationPasses: UInt32 = 3

    /// The key deriver for the given parameters, as read from an encrypted vault's header.
    public static func keyDeriver(parameters: Argon2idParameters) -> Argon2idKeyDeriver<32> {
        Argon2idKeyDeriver(parameters: parameters)
    }
}

/// The key derivation parameters calibration chose for this device, and the times that go with them.
public struct AppLockKeyDerivationCalibration: Equatable, Sendable {
    /// The parameters to store in the new encrypted vault's header.
    public var parameters: Argon2idParameters
    /// How long a derivation with `parameters` should take on this device.
    public var expectedDerivationDuration: Duration
    /// How long unlocking takes on this device, however quickly it could finish. Every unlock attempt (real,
    /// duress or wrong) finishes at this deadline, so how long it takes reveals nothing.
    public var unlockDeadline: Duration

    public init(parameters: Argon2idParameters, expectedDerivationDuration: Duration, unlockDeadline: Duration) {
        self.parameters = parameters
        self.expectedDerivationDuration = expectedDerivationDuration
        self.unlockDeadline = unlockDeadline
    }
}

/// Times one Argon2id derivation.
public protocol Argon2idDerivationTiming: Sendable {
    /// Runs one derivation with `parameters` and returns how long it took.
    func timeDerivation(parameters: Argon2idParameters) throws -> Duration
}

/// Times real derivations, with a random password and salt.
public struct Argon2idDerivationTimer: Argon2idDerivationTiming {
    public init() {}

    public func timeDerivation(parameters: Argon2idParameters) throws -> Duration {
        let deriver = Argon2idKeyDeriver<32>(parameters: parameters)
        let password = Data.random(count: 16)
        let salt = Data.random(count: 32)
        let start = ContinuousClock.now
        _ = try deriver.key(password: password, salt: salt)
        return ContinuousClock.now - start
    }
}

/// Chooses the app lock key derivation parameters for this device.
///
/// It times a few derivations over the full 64 MiB, works out how long one pass takes, and chooses as many passes
/// as fit in `AppLockKeyDerivation.targetDuration`, within `AppLockKeyDerivation.passesRange`.
public struct AppLockKeyDerivationCalibrator: Sendable {
    private let timer: any Argon2idDerivationTiming

    public init(timer: any Argon2idDerivationTiming = Argon2idDerivationTimer()) {
        self.timer = timer
    }

    /// Times the derivations and chooses the parameters. This takes a few tenths of a second to a couple of
    /// seconds, so run it off the main actor.
    public func calibrate() throws -> AppLockKeyDerivationCalibration {
        let runParameters = Argon2idParameters(
            memoryKiB: AppLockKeyDerivation.memoryKiB,
            iterations: AppLockKeyDerivation.calibrationPasses,
            parallelism: 1,
        )
        var fastest: Duration?
        for _ in 0 ..< AppLockKeyDerivation.calibrationRuns {
            let duration = try timer.timeDerivation(parameters: runParameters)
            fastest = min(fastest ?? duration, duration)
        }
        let timePerPass = (fastest ?? .zero) / Int(AppLockKeyDerivation.calibrationPasses)
        let passes = Self.passes(timePerPass: timePerPass)
        let expectedDuration = timePerPass * Int(passes)
        return AppLockKeyDerivationCalibration(
            parameters: Argon2idParameters(
                memoryKiB: AppLockKeyDerivation.memoryKiB,
                iterations: passes,
                parallelism: 1,
            ),
            expectedDerivationDuration: expectedDuration,
            unlockDeadline: expectedDuration * AppLockKeyDerivation.deadlineMultiplier,
        )
    }

    /// As many whole passes as fit in the target duration, within the allowed range.
    static func passes(timePerPass: Duration) -> UInt32 {
        let range = AppLockKeyDerivation.passesRange
        guard timePerPass > .zero else { return range.upperBound }
        let fitting = (AppLockKeyDerivation.targetDuration / timePerPass).rounded(.down)
        let clamped = min(max(fitting, Double(range.lowerBound)), Double(range.upperBound))
        return UInt32(clamped)
    }
}
