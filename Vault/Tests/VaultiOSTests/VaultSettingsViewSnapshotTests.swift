import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
struct VaultSettingsViewSnapshotTests {
    @Test
    func layout() throws {
        let sut = try makeSUT()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_dark() throws {
        let sut = try makeSUT()

        assertSnapshot(of: sut, colorScheme: .dark)
    }

    @Test
    func layout_largeText() throws {
        let sut = try makeSUT(dynamicTypeSize: .accessibility2, height: 2800)

        assertSnapshot(of: sut, as: .image)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func universalClipboardOn(colorScheme: ColorScheme) throws {
        let sut = try makeSUT { state in
            state.allowUniversalClipboardForOTPs = true
            state.allowUniversalClipboardForNotes = true
        }

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test
    func universalClipboardCodesOnly() throws {
        let sut = try makeSUT { state in
            state.allowUniversalClipboardForOTPs = true
        }

        assertSnapshot(of: sut, as: .image)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func hideWhileRecordingOff(colorScheme: ColorScheme) throws {
        let sut = try makeSUT { state in
            state.hidesVaultWhileScreenCaptured = false
        }

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func newItemDefaultsOn(colorScheme: ColorScheme) throws {
        let sut = try makeSUT { state in
            state.lockNewItems = true
            state.showNewCodesInQuickType = true
        }

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func tapCodeToShowDetails(colorScheme: ColorScheme) throws {
        let sut = try makeSUT { state in
            state.codeTapAction = .showDetails
        }

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func showNextCodeOn(colorScheme: ColorScheme) throws {
        let sut = try makeSUT { state in
            state.showsNextCode = true
        }

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func appLockOn(colorScheme: ColorScheme) throws {
        let sut = try makeSUT(isAppLockEnabled: true)

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func appLockWithDelay(colorScheme: ColorScheme) throws {
        let sut = try makeSUT(isAppLockEnabled: true, appLockDelay: .fiveMinutes)

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func appLockPasswordOff(colorScheme: ColorScheme) throws {
        let sut = try makeSUT(isAppLockEnabled: true, passwordService: FakeAppLockPasswordService())

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    /// The lock can't be turned off while the password is on.
    @Test(arguments: [ColorScheme.light, .dark])
    func appLockPasswordOn(colorScheme: ColorScheme) async throws {
        let sut = try await makeSUT(
            isAppLockEnabled: true,
            passwordService: FakeAppLockPasswordService(password: "correct horse"),
            unlockingWith: "correct horse",
        )

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func appLockWithoutPasscode(colorScheme: ColorScheme) throws {
        let sut = try makeSUT(policy: .cannotAuthenticate)

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }
}

// MARK: - Helpers

extension VaultSettingsViewSnapshotTests {
    private func makeSUT(
        dynamicTypeSize: DynamicTypeSize = .medium,
        height: CGFloat = 1500,
        isAppLockEnabled: Bool = false,
        appLockDelay: AppLockDelay = .immediately,
        policy: some DeviceAuthenticationPolicy = .alwaysDeny,
        passwordService: FakeAppLockPasswordService? = nil,
        configure: (inout LocalSettingsState) -> Void = { _ in },
    ) throws -> some View {
        let authenticationService = DeviceAuthenticationService(policy: policy)
        let appLock = try makeAppLock(
            isEnabled: isAppLockEnabled,
            delay: appLockDelay,
            authenticationService: authenticationService,
            passwordService: passwordService,
        )
        return try makeSUT(
            appLock: appLock,
            authenticationService: authenticationService,
            dynamicTypeSize: dynamicTypeSize,
            height: height,
            configure: configure,
        )
    }

    /// Settings with an App Lock Password that's set, once the app is unlocked with it.
    private func makeSUT(
        isAppLockEnabled: Bool,
        passwordService: FakeAppLockPasswordService,
        unlockingWith password: String,
    ) async throws -> some View {
        let authenticationService = DeviceAuthenticationService(policy: .alwaysAllow)
        let appLock = try makeAppLock(
            isEnabled: isAppLockEnabled,
            delay: .immediately,
            authenticationService: authenticationService,
            passwordService: passwordService,
        )
        await appLock.unlock()
        await appLock.unlock(password: password)
        return try makeSUT(appLock: appLock, authenticationService: authenticationService)
    }

    private func makeAppLock(
        isEnabled: Bool,
        delay: AppLockDelay,
        authenticationService: DeviceAuthenticationService,
        passwordService: FakeAppLockPasswordService?,
    ) throws -> AppLockService {
        let appLockSettings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        appLockSettings.isEnabled = isEnabled
        appLockSettings.delay = delay
        return AppLockService(
            settings: appLockSettings,
            authenticationService: authenticationService,
            passwordService: passwordService,
            purgeSensitiveData: {},
        )
    }

    private func makeSUT(
        appLock: AppLockService,
        authenticationService: DeviceAuthenticationService,
        dynamicTypeSize: DynamicTypeSize = .medium,
        height: CGFloat = 1500,
        configure: (inout LocalSettingsState) -> Void = { _ in },
    ) throws -> some View {
        let localSettings = try LocalSettings(defaults: .nonPersistent())
        configure(&localSettings.state)
        return VaultSettingsView(viewModel: .init(), localSettings: localSettings)
            .environment(anyVaultDataModel())
            .environment(authenticationService)
            .environment(appLock)
            .dynamicTypeSize(dynamicTypeSize)
            .framedForTest(height: height)
    }
}
