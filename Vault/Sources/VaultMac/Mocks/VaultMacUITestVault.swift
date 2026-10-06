#if DEBUG
import FoundationExtensions
import LocalAuthentication
import VaultFeed

/// What the Mac app's UI tests launch it with, in `VaultApp/VaultMacAppUITests`.
///
/// Like the iOS app's `UITestVault`, the app then runs on `UITestVaultStorage`: a directory, defaults and keychain
/// items
/// of its own, so the Mac's own vault is never read or written.
///
/// - `-ui-test-vault fresh` empties that storage, so the app starts as it does the first time it's opened.
///   `-ui-test-vault open` opens what the last launch left there.
/// - `-ui-test-authentication <answers>` is how Touch ID or the Mac's password answers: `allow`, `deny` or `cancel`,
///   one for each prompt in turn and the last for every prompt after it, separated by commas. Or `unavailable`, as on a
///   Mac with no login password. `allow` if it isn't given.
/// - `-ui-test-app-lock-delay <seconds>` sets Require Unlock, by the number of seconds it's stored as.
///
/// A value that isn't one of these is a bug in a test, so it fails loudly. Compiled out of release builds.
enum VaultMacUITestVault {
    /// The App Lock Password the UI tests set.
    static let password = "correct horse battery"

    /// Stands in for Touch ID and the Mac's password, for a launch for UI tests.
    static let authenticationPolicy: (any DeviceAuthenticationPolicy)? = arguments.authenticationPolicy

    /// Require Unlock, if a UI test sets it.
    static let appLockDelay: AppLockDelay? = arguments.appLockDelay

    /// Cheap key derivation for a UI test's App Lock Password, so its vault opens in moments.
    static let keyDerivationCalibration: AppLockKeyDerivationCalibration? = arguments.isEnabled
        ? AppLockKeyDerivationCalibration(
            parameters: Argon2idParameters(memoryKiB: 64, iterations: 1, parallelism: 1),
            expectedDerivationDuration: .milliseconds(10),
            unlockDeadline: .milliseconds(200),
        )
        : nil

    private static let arguments = Arguments(ProcessInfo.processInfo.arguments)

    /// What the command line asks for.
    struct Arguments {
        var isEnabled = false
        var authenticationPolicy: (any DeviceAuthenticationPolicy)?
        var appLockDelay: AppLockDelay?

        init(_ arguments: [String]) {
            guard let vault = Self.value(after: UITestVaultStorage.launchArgument, in: arguments) else { return }
            guard ["fresh", UITestVaultStorage.openValue].contains(vault) else {
                Self.fail(UITestVaultStorage.launchArgument, vault, expected: ["fresh", UITestVaultStorage.openValue])
            }
            isEnabled = true
            authenticationPolicy = Self.policy(Self.value(after: "-ui-test-authentication", in: arguments) ?? "allow")
            if let delay = Self.value(after: "-ui-test-app-lock-delay", in: arguments) {
                guard let seconds = Int(delay), let appLockDelay = AppLockDelay(rawValue: seconds) else {
                    Self.fail(
                        "-ui-test-app-lock-delay",
                        delay,
                        expected: AppLockDelay.allCases.map { "\($0.rawValue)" },
                    )
                }
                self.appLockDelay = appLockDelay
            }
        }

        private static func value(after argument: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: argument) else { return nil }
            return arguments.dropFirst(index + 1).first ?? ""
        }

        private static func policy(_ value: String) -> any DeviceAuthenticationPolicy {
            if value == "unavailable" {
                return .cannotAuthenticate
            }
            let answers = value.split(separator: ",").map { answer in
                guard let parsed = VaultMacUITestAuthenticationPolicy.Answer(rawValue: String(answer)) else {
                    fail(
                        "-ui-test-authentication",
                        value,
                        expected: VaultMacUITestAuthenticationPolicy.Answer.allCases.map(\.rawValue),
                    )
                }
                return parsed
            }
            guard answers.isNotEmpty else {
                fail(
                    "-ui-test-authentication",
                    value,
                    expected: VaultMacUITestAuthenticationPolicy.Answer.allCases.map(\.rawValue),
                )
            }
            return VaultMacUITestAuthenticationPolicy(answers: answers)
        }

        private static func fail(_ argument: String, _ value: String, expected: [String]) -> Never {
            fatalError("Unknown \(argument) '\(value)'. Expected one of: \(expected.joined(separator: ", "))")
        }
    }
}

/// Answers Touch ID or the Mac's password as a UI test says: one answer for each prompt in turn, and the last for every
/// prompt after it.
struct VaultMacUITestAuthenticationPolicy: DeviceAuthenticationPolicy {
    enum Answer: String, CaseIterable, Sendable {
        /// The user passes.
        case allow
        /// The user doesn't pass.
        case deny
        /// The user dismisses the prompt.
        case cancel
    }

    private let answers: SharedMutex<[Answer]>

    init(answers: [Answer]) {
        self.answers = SharedMutex(answers)
    }

    var canAuthenicateWithPasscode: Bool {
        true
    }

    var canAuthenticateWithBiometrics: Bool {
        true
    }

    func authenticateWithBiometrics(reason _: String) async throws -> Bool {
        switch nextAnswer() {
        case .allow: true
        case .deny: false
        case .cancel: throw LAError(.userCancel)
        }
    }

    func authenticateWithPasscode(reason: String) async throws -> Bool {
        try await authenticateWithBiometrics(reason: reason)
    }

    private func nextAnswer() -> Answer {
        answers.modify { answers in
            answers.count > 1 ? answers.removeFirst() : answers[0]
        }
    }
}
#endif
