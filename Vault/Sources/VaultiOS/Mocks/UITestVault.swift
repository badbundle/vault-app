#if DEBUG
import FoundationExtensions
import LocalAuthentication
import SwiftUI
import VaultFeed

/// Launch-argument driven vaults with the lock on, for the UI tests in `VaultApp/VaultAppUITests`.
///
/// Each runs on `UITestVaultStorage`: a directory, defaults and keychain items of its own, so the simulator's own vault
/// is never read or written. A test has the app prepare a vault in a launch of its own, then launches it again on
/// that vault, which it starts on just as it would on a device:
///
/// - `-ui-test-vault <preset>` empties the storage, prepares the `Preset` there, then shows `preparedIdentifier`.
/// - `-ui-test-vault open` opens the vault the last launch prepared.
/// - `-ui-test-authentication <answers>` is how device authentication answers: `allow`, `deny` or `cancel`, one for
///   each prompt in turn and the last for every prompt after it, separated by commas. Or `unavailable`, as on a device
///   with no passcode. `allow` if it isn't given.
/// - `-ui-test-app-lock-delay <seconds>` sets Require Unlock, by the number of seconds it's stored as.
///
/// A value that isn't one of these is a bug in a test rather than a user error, so it fails loudly, as
/// `ScreenshotMode` does. Compiled out of release builds.
enum UITestVault {
    /// A vault the app prepares for a test.
    enum Preset: String, CaseIterable {
        /// App Lock on, asking for device authentication only, over the demo vault `ScreenshotMode` seeds.
        case appLock = "app-lock"
        /// The App Lock Password set over the demo vault, and a duress password, which opens a vault of its own with
        /// `duressItems` in it.
        case appLockPassword = "app-lock-password"
    }

    static let password = "correct horse battery"
    static let duressPassword = "plausible decoy"

    /// Identifies what the app shows once it's prepared a vault.
    static let preparedIdentifier = "ui-test-vault.prepared"

    /// The vault to prepare, or `nil` for a launch that opens a prepared vault, or one that isn't for UI tests.
    static let preset: Preset? = arguments.preset

    /// Stands in for Face ID and the device passcode, for a launch for UI tests.
    static let authenticationPolicy: (any DeviceAuthenticationPolicy)? = arguments.authenticationPolicy

    /// Require Unlock, if a UI test sets it.
    static let appLockDelay: AppLockDelay? = arguments.appLockDelay

    /// Cheap key derivation for a UI test's App Lock Password, so its vault opens in moments rather than half a
    /// second a try.
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
        var preset: Preset?
        var authenticationPolicy: (any DeviceAuthenticationPolicy)?
        var appLockDelay: AppLockDelay?

        init(_ arguments: [String]) {
            guard let vault = Self.value(after: UITestVaultStorage.launchArgument, in: arguments) else { return }
            guard !ScreenshotMode.isEnabled else {
                fatalError(
                    "\(ScreenshotMode.launchArgument) and \(UITestVaultStorage.launchArgument) can't be used together",
                )
            }
            isEnabled = true
            if vault != UITestVaultStorage.openValue {
                preset = Self.parse(vault, argument: UITestVaultStorage.launchArgument)
            }
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
            let answers: [UITestAuthenticationPolicy.Answer] = value.split(separator: ",").map {
                parse(String($0), argument: "-ui-test-authentication")
            }
            guard answers.isNotEmpty else {
                fail(
                    "-ui-test-authentication",
                    value,
                    expected: UITestAuthenticationPolicy.Answer.allCases.map(\.rawValue),
                )
            }
            return UITestAuthenticationPolicy(answers: answers)
        }

        private static func parse<Value: RawRepresentable<String> & CaseIterable>(
            _ value: String,
            argument: String,
        ) -> Value {
            guard let parsed = Value(rawValue: value) else {
                fail(argument, value, expected: Value.allCases.map(\.rawValue))
            }
            return parsed
        }

        private static func fail(_ argument: String, _ value: String, expected: [String]) -> Never {
            fatalError("Unknown \(argument) '\(value)'. Expected one of: \(expected.joined(separator: ", "))")
        }
    }

    /// The duress vault's items: nothing the demo vault has.
    static var duressItems: [VaultItem.Write] {
        let factory = VaultItemDemoFactory()
        return [factory.makeTOTPCode(), factory.makeSecureNote()]
    }

    /// Prepares `preset` in the empty storage the app has opened, with the App Lock Password service Settings sets the
    /// password with. The lock is left off in this launch, and the next launch finds it on.
    @MainActor
    static func prepare(_ preset: Preset) async throws {
        _ = try await ScreenshotMode.seed(
            store: VaultRoot.vaultStore,
            dataModel: VaultRoot.vaultDataModel,
            backupEventLogger: VaultRoot.backupEventLogger,
        )
        VaultRoot.appLockSettingsStore.isEnabled = true
        guard preset == .appLockPassword else { return }
        guard let passwordService = VaultRoot.vaultPasswordService else {
            fatalError("UI tests need the App Lock Password")
        }
        try await passwordService.setPassword(password, deletingSetAsideVaults: false)
        guard try await passwordService.makeDuressVault(current: password, password: duressPassword) == .accepted else {
            fatalError("The duress password wasn't set")
        }
        // A duress vault starts empty, so its password opens it to put its items in.
        await passwordService.lockVault()
        guard try await passwordService.unlock(password: duressPassword) == .accepted else {
            fatalError("The duress password didn't open its vault")
        }
        for item in duressItems {
            _ = try await VaultRoot.vaultStore.insert(item: item)
        }
        await passwordService.lockVault()
    }
}

/// Prepares a UI test's vault, then says so, for the test to launch the app again on it.
struct UITestVaultPreparationView: View {
    var preset: UITestVault.Preset

    @State private var isPrepared = false

    var body: some View {
        Group {
            if isPrepared {
                Text(verbatim: "Prepared")
                    .accessibilityIdentifier(UITestVault.preparedIdentifier)
            } else {
                Color.clear
            }
        }
        .task {
            do {
                try await UITestVault.prepare(preset)
                isPrepared = true
            } catch {
                fatalError("Unable to prepare the UI test vault: \(error)")
            }
        }
    }
}

/// Answers device authentication as a UI test says: one answer for each prompt in turn, and the last for every prompt
/// after it.
struct UITestAuthenticationPolicy: DeviceAuthenticationPolicy {
    enum Answer: String, CaseIterable, Sendable {
        /// The user passes, as with a face that's recognised.
        case allow
        /// The user doesn't pass, as with a face that isn't.
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
