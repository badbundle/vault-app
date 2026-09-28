#if DEBUG
import Foundation
import LocalAuthentication
import Testing
import VaultFeed
@testable import VaultiOS

/// The UI tests' launch arguments change nothing unless they're given, and they're only in debug builds.
struct UITestVaultTests {
    @Test
    func withoutTheLaunchArguments_changesNothing() {
        #expect(UITestVault.preset == nil)
        #expect(UITestVault.authenticationPolicy == nil)
        #expect(UITestVault.appLockDelay == nil)
        #expect(UITestVault.keyDerivationCalibration == nil)
    }

    @Test
    func arguments_toPrepareAVault_nameThePresetAndAllowByDefault() async throws {
        let arguments = UITestVault.Arguments(["-ui-test-vault", "app-lock-password"])

        #expect(arguments.isEnabled)
        #expect(arguments.preset == .appLockPassword)
        #expect(arguments.appLockDelay == nil)
        let policy = try #require(arguments.authenticationPolicy)
        #expect(try await policy.authenticate(reason: "Test"))
    }

    @Test
    func arguments_toOpenAPreparedVault_prepareNothing() {
        let arguments = UITestVault.Arguments(["-ui-test-vault", "open", "-ui-test-app-lock-delay", "900"])

        #expect(arguments.isEnabled)
        #expect(arguments.preset == nil)
        #expect(arguments.appLockDelay == .fifteenMinutes)
    }

    @Test
    func arguments_withAuthenticationUnavailable_cannotAuthenticate() throws {
        let arguments = UITestVault.Arguments(["-ui-test-vault", "open", "-ui-test-authentication", "unavailable"])

        let policy = try #require(arguments.authenticationPolicy)
        #expect(!policy.canAuthenticate)
    }

    @Test
    func authenticationPolicy_answersEachPromptInTurn_thenRepeatsTheLast() async throws {
        let arguments = UITestVault.Arguments([
            "-ui-test-vault",
            "open",
            "-ui-test-authentication",
            "cancel,deny,allow",
        ])
        let policy = try #require(arguments.authenticationPolicy)

        await #expect(throws: LAError.self) {
            try await policy.authenticate(reason: "Test")
        }
        #expect(try await !policy.authenticate(reason: "Test"))
        #expect(try await policy.authenticate(reason: "Test"))
        #expect(try await policy.authenticate(reason: "Test"))
    }
}
#endif
