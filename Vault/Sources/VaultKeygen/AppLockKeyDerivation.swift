import CryptoEngine
import Foundation
import FoundationExtensions

/// How the app lock password derives its key: Argon2id over 64 MiB, with the number of lanes and passes calibrated on
/// the device that creates the encrypted vault (see `docs/on-device-encryption.md`, "Key derivation").
///
/// The parameters are chosen once, when the encrypted file is created, and stored in its header. Every vault in the
/// file derives with them from then on, so they can't be tuned per vault or raised later. A file made before VAULT-128
/// keeps the half second, single lane and at most 32 passes it was calibrated with then.
public enum AppLockKeyDerivation {
    /// The memory every derivation uses: 64 MiB, which the AutoFill extension can spare.
    public static let memoryKiB: UInt32 = 64 * 1024
    /// The passes calibration can choose. The floor is RFC 9106's recommended 3 passes at 64 MiB, which a device too
    /// slow to fit them in the target still gets. The ceiling keeps unlocking bounded if a very fast device calibrates
    /// and the file is later restored to a slower one.
    ///
    /// A Vault older than VAULT-128 reads files with at most 32 passes, so it can't open a file with more. The app and
    /// its extensions always ship together, so they always agree.
    public static let passesRange: ClosedRange<UInt32> = 3 ... 128
    /// The numbers of lanes calibration chooses between. Each lane runs on a thread of its own, so a device with the
    /// cores to run them side by side fits more passes in the target.
    public static let laneCounts: [UInt32] = [1, 2, 4]
    /// How long calibration aims for one derivation to take.
    public static let targetDuration: Duration = .seconds(1)
    /// The unlock deadline, as a multiple of the expected derivation time. The rest is time to try the vault slots
    /// and decode the vault.
    public static let deadlineMultiplier = 1.5
    /// The number of timed derivations calibration makes with each number of lanes. It uses the fastest, so a moment
    /// when the device is busy can't make it choose too few passes.
    public static let calibrationRuns = 3
    /// The passes each timed derivation makes: a short run, which calibration extrapolates from.
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
/// For each number of lanes in `AppLockKeyDerivation.laneCounts`, it times a few short derivations over the full
/// 64 MiB and works out how long one pass takes. Each gets as many passes as fit in
/// `AppLockKeyDerivation.targetDuration`, within `AppLockKeyDerivation.passesRange`, and it chooses the lanes that fit
/// the most. Every pass works through all 64 MiB however many lanes share it, so the most passes is the most work for
/// anyone guessing the password. If more than one fits as many, as at the floor or the ceiling, it chooses the
/// quickest.
public struct AppLockKeyDerivationCalibrator: Sendable {
    /// What calibration measured for one number of lanes.
    public struct LaneMeasurement: Equatable, Sendable {
        public var lanes: UInt32
        /// How long one pass takes with these lanes, from the fastest timed derivation.
        public var timePerPass: Duration

        /// As many whole passes as fit in the target with these lanes, within the allowed range.
        public var passes: UInt32 {
            AppLockKeyDerivationCalibrator.passes(timePerPass: timePerPass)
        }

        /// How long a derivation with these lanes and `passes` should take.
        public var expectedDuration: Duration {
            timePerPass * Int(passes)
        }

        /// Whether these lanes fit more passes than the other's, or as many more quickly.
        func isBetterChoice(than other: LaneMeasurement) -> Bool {
            passes == other.passes ? expectedDuration < other.expectedDuration : passes > other.passes
        }
    }

    private let timer: any Argon2idDerivationTiming

    public init(timer: any Argon2idDerivationTiming = Argon2idDerivationTimer()) {
        self.timer = timer
    }

    /// Times the derivations and chooses the parameters. This takes a few tenths of a second to a second or so, so
    /// run it off the main actor.
    public func calibrate() throws -> AppLockKeyDerivationCalibration {
        try Self.calibration(choosingFrom: measureLanes())
    }

    /// Times `AppLockKeyDerivation.calibrationRuns` short derivations with each number of lanes, and measures how long
    /// a pass takes with each, in the order of `AppLockKeyDerivation.laneCounts`.
    ///
    /// The runs take turns between the numbers of lanes, so a moment when the device is busy slows one run of each
    /// rather than every run of one.
    public func measureLanes() throws -> [LaneMeasurement] {
        var fastest = [UInt32: Duration]()
        for _ in 0 ..< AppLockKeyDerivation.calibrationRuns {
            for lanes in AppLockKeyDerivation.laneCounts {
                let duration = try timer.timeDerivation(parameters: Argon2idParameters(
                    memoryKiB: AppLockKeyDerivation.memoryKiB,
                    iterations: AppLockKeyDerivation.calibrationPasses,
                    parallelism: lanes,
                ))
                fastest[lanes] = min(fastest[lanes] ?? duration, duration)
            }
        }
        return AppLockKeyDerivation.laneCounts.map { lanes in
            LaneMeasurement(
                lanes: lanes,
                timePerPass: (fastest[lanes] ?? .zero) / Int(AppLockKeyDerivation.calibrationPasses),
            )
        }
    }

    /// The parameters of the lanes that fit the most passes, or as many most quickly, and the times that go with them.
    public static func calibration(choosingFrom measurements: [LaneMeasurement]) -> AppLockKeyDerivationCalibration {
        precondition(measurements.isNotEmpty, "Calibration chooses from at least one number of lanes")
        let chosen = measurements.dropFirst().reduce(measurements[0]) { $1.isBetterChoice(than: $0) ? $1 : $0 }
        let expectedDuration = chosen.expectedDuration
        return AppLockKeyDerivationCalibration(
            parameters: Argon2idParameters(
                memoryKiB: AppLockKeyDerivation.memoryKiB,
                iterations: chosen.passes,
                parallelism: chosen.lanes,
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
