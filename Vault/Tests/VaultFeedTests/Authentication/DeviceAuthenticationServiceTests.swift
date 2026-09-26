import Foundation
import LocalAuthentication
import TestHelpers
import Testing
@testable import VaultFeed

@MainActor
struct DeviceAuthenticationServiceTests {
    @Test
    func canAuthenticateWithNeither() {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: false,
        )
        let sut = makeSUT(policy: policy)

        #expect(!sut.canAuthenticate)
    }

    @Test
    func canAuthenticateWithBiometrics() {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: true,
        )
        let sut = makeSUT(policy: policy)

        #expect(sut.canAuthenticate)
    }

    @Test
    func canAuthenticateWithPasscode() {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: false,
        )
        let sut = makeSUT(policy: policy)

        #expect(sut.canAuthenticate)
    }

    @Test
    func canAuthenticateWithBoth() {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        let sut = makeSUT(policy: policy)

        #expect(sut.canAuthenticate)
    }

    @Test
    func authenticateNoneEnabledFails() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: false,
        )
        let sut = makeSUT(policy: policy)

        let result = try await sut.authenticate(reason: "reason")
        #expect(result == .failure(.noAuthenticationSetup))
        #expect(policy.authenticateWithBiometricsCallCount == 0)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    @Test
    func authenticateBiometricsEnabledSuccess() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { reason in
            #expect(reason == "reason")
            return true
        }
        let sut = makeSUT(policy: policy)

        let result = try await sut.authenticate(reason: "reason")
        #expect(result == .success(.authenticated))
        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    @Test
    func authenticateBiometricsEnabledFailure() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { reason in
            #expect(reason == "reason")
            return false
        }
        let sut = makeSUT(policy: policy)

        let result = try await sut.authenticate(reason: "reason")
        #expect(result == .failure(.authenticationFailure))
        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    @Test
    func authenticateBiometricsInternalError() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { reason in
            #expect(reason == "reason")
            throw TestError()
        }
        let sut = makeSUT(policy: policy)

        await #expect(throws: (any Error).self) {
            try await sut.authenticate(reason: "reason")
        }
        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    @Test
    func authenticatePasscodeEnabledSuccess() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: false,
        )
        policy.authenticateWithPasscodeHandler = { reason in
            #expect(reason == "reason")
            return true
        }
        let sut = makeSUT(policy: policy)

        let result = try await sut.authenticate(reason: "reason")
        #expect(result == .success(.authenticated))
        #expect(policy.authenticateWithBiometricsCallCount == 0)
        #expect(policy.authenticateWithPasscodeCallCount == 1)
    }

    @Test
    func authenticatePasscodeEnabledFailure() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: false,
        )
        policy.authenticateWithPasscodeHandler = { reason in
            #expect(reason == "reason")
            return false
        }
        let sut = makeSUT(policy: policy)

        let result = try await sut.authenticate(reason: "reason")
        #expect(result == .failure(.authenticationFailure))
        #expect(policy.authenticateWithBiometricsCallCount == 0)
        #expect(policy.authenticateWithPasscodeCallCount == 1)
    }

    @Test
    func authenticatePasscodeInternalError() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: false,
        )
        policy.authenticateWithPasscodeHandler = { reason in
            #expect(reason == "reason")
            throw TestError()
        }
        let sut = makeSUT(policy: policy)

        await #expect(throws: (any Error).self) {
            try await sut.authenticate(reason: "reason")
        }
        #expect(policy.authenticateWithBiometricsCallCount == 0)
        #expect(policy.authenticateWithPasscodeCallCount == 1)
    }

    @Test
    func authenticateBothEnabledAuthenticatesWithBiometrics() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { reason in
            #expect(reason == "reason")
            return true
        }
        let sut = makeSUT(policy: policy)

        _ = try await sut.authenticate(reason: "reason")
        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    @Test
    func policyExtension_authenticateReturnsFalseWhenNoPolicyAvailable() async throws {
        let policy = DeviceAuthenticationPolicyCannotAuthenticate()

        let result = try await policy.authenticate(reason: "reason")
        let cannotAuthenticate: DeviceAuthenticationPolicyCannotAuthenticate = .cannotAuthenticate

        #expect(policy.canAuthenticate == false)
        #expect(result == false)
        #expect(cannotAuthenticate.canAuthenticate == false)
    }

    @Test
    func policyExtension_authenticateUsesPasscodeWhenBiometricsUnavailable() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: false,
        )
        policy.authenticateWithPasscodeHandler = { reason in
            #expect(reason == "reason")
            return true
        }

        let result = try await policy.authenticate(reason: "reason")

        #expect(result)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
        #expect(policy.authenticateWithPasscodeCallCount == 1)
    }

    @Test
    func staticPolicies_allowAndDenyAuthentication() async throws {
        let allow = DeviceAuthenticationPolicyAlwaysAllow()
        let deny = DeviceAuthenticationPolicyAlwaysDeny()

        #expect(allow.canAuthenicateWithPasscode)
        #expect(allow.canAuthenticateWithBiometrics)
        #expect(try await allow.authenticateWithPasscode(reason: "reason"))
        #expect(try await allow.authenticateWithBiometrics(reason: "reason"))

        #expect(deny.canAuthenicateWithPasscode)
        #expect(deny.canAuthenticateWithBiometrics)
        #expect(try await deny.authenticateWithPasscode(reason: "reason") == false)
        #expect(try await deny.authenticateWithBiometrics(reason: "reason") == false)

        let factoryAllow: DeviceAuthenticationPolicyAlwaysAllow = .alwaysAllow
        let factoryDeny: DeviceAuthenticationPolicyAlwaysDeny = .alwaysDeny

        #expect(try await factoryAllow.authenticate(reason: "reason"))
        #expect(try await factoryDeny.authenticate(reason: "reason") == false)
    }

    @Test
    func devicePolicyDefaultFactoriesCreateUsingDevicePolicy() {
        let defaultPolicy: DeviceAuthenticationPolicyUsingDevice = .default
        let usingDevicePolicy: DeviceAuthenticationPolicyUsingDevice = .usingDevice

        _ = defaultPolicy
        _ = usingDevicePolicy
    }

    @Test
    func authenticate_biometricFallbackAsksForThePasscode() async throws {
        // "Enter Password" in the Face ID prompt.
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            throw LAError(.userFallback)
        }
        policy.authenticateWithPasscodeHandler = { reason in
            #expect(reason == "reason")
            return true
        }
        let sut = makeSUT(policy: policy)

        let result = try await sut.authenticate(reason: "reason")

        #expect(result == .success(.authenticated))
        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(policy.authenticateWithPasscodeCallCount == 1)
    }

    @Test
    func authenticate_biometricCancelDoesNotAskForThePasscode() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            throw LAError(.userCancel)
        }
        let sut = makeSUT(policy: policy)

        await #expect(throws: LAError.self) {
            try await sut.authenticate(reason: "reason")
        }
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    @Test
    func isAuthenticating_isTrueOnlyWhileAPromptIsUp() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        let sut = makeSUT(policy: policy)
        // Passes only if the service says it's authenticating while the prompt is up.
        policy.authenticateWithBiometricsHandler = { _ in
            await sut.isAuthenticating
        }

        #expect(!sut.isAuthenticating)
        let result = try await sut.authenticate(reason: "reason")
        #expect(result == .success(.authenticated))
        #expect(!sut.isAuthenticating)

        try await sut.validateAuthentication(reason: "reason")
        #expect(!sut.isAuthenticating)
    }

    @Test
    func isAuthenticating_isFalseAfterAPromptFails() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            throw TestError()
        }
        let sut = makeSUT(policy: policy)

        _ = try? await sut.authenticate(reason: "reason")
        try? await sut.validateAuthentication(reason: "reason")

        #expect(!sut.isAuthenticating)
    }

    @Test
    func validateAuthenticationDoesNotThrowIfValid() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { reason in
            #expect(reason == "reason")
            return true
        }
        let sut = makeSUT(policy: policy)

        await #expect(throws: Never.self) {
            try await sut.validateAuthentication(reason: "reason")
        }
        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    @Test
    func validateAuthenticationThrowsForNotAuthenticated() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { reason in
            #expect(reason == "reason")
            return false
        }
        let sut = makeSUT(policy: policy)

        await #expect(throws: (any Error).self) {
            try await sut.validateAuthentication(reason: "reason")
        }
    }

    @Test
    func validateAuthenticationThrowsForInternalError() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { reason in
            #expect(reason == "reason")
            throw TestError()
        }
        let sut = makeSUT(policy: policy)

        await #expect(throws: (any Error).self) {
            try await sut.validateAuthentication(reason: "reason")
        }
    }
}

// MARK: - Helpers

extension DeviceAuthenticationServiceTests {
    private func makeSUT(
        policy: DeviceAuthenticationPolicyMock = DeviceAuthenticationPolicyMock(),
    ) -> DeviceAuthenticationService {
        DeviceAuthenticationService(policy: policy)
    }
}
