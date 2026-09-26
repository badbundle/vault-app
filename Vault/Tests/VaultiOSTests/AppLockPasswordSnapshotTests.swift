import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultFeed
@testable import VaultiOS

/// The App Lock Password's screens in Settings.
@MainActor
struct AppLockPasswordSnapshotTests {
    private static let password = "correct horse"

    // MARK: - Setting

    @Test
    func setup() async throws {
        try await snapshotScenarios(dynamicTypeSizes: [.medium, .xxLarge]) {
            try AppLockPasswordFormViewModel(purpose: .set, appLock: makeAppLock(password: nil))
        }
    }

    @Test
    func setupWithBackup() async throws {
        let backup = VaultBackupEvent(
            backupDate: Date(timeIntervalSince1970: 1_790_000_000),
            eventDate: Date(timeIntervalSince1970: 1_790_000_000),
            kind: .exportedToPDF,
            payloadHash: .init(value: Data(repeating: 1, count: 32)),
        )

        try await snapshotScenarios(lastBackup: backup) {
            try AppLockPasswordFormViewModel(purpose: .set, appLock: makeAppLock(password: nil))
        }
    }

    /// Says what's wrong with the password and its confirmation, and can't be submitted.
    @Test
    func setupWeakPassword() async throws {
        try await snapshotScenarios {
            let viewModel = try AppLockPasswordFormViewModel(purpose: .set, appLock: makeAppLock(password: nil))
            viewModel.newPassword = "12345678"
            viewModel.confirmation = "1234567"
            return viewModel
        }
    }

    @Test
    func setupDone() async throws {
        try await snapshotScenarios {
            let viewModel = try AppLockPasswordFormViewModel(purpose: .set, appLock: makeAppLock(password: nil))
            viewModel.newPassword = Self.password
            viewModel.confirmation = Self.password
            await viewModel.submit()
            return viewModel
        }
    }

    // MARK: - Password on

    @Test
    func manage() async throws {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.medium, .xxLarge] {
                let appLock = try await makeUnlockedAppLock()
                let view = AppLockPasswordManageView(close: {})
                    .environment(appLock)
                snapshot(view, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize)
            }
        }
    }

    @Test
    func change() async throws {
        try await snapshotScenarios(dynamicTypeSizes: [.medium, .xxLarge]) {
            try await AppLockPasswordFormViewModel(purpose: .change, appLock: makeUnlockedAppLock())
        }
    }

    @Test
    func changeWrongPassword() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .change, appLock: makeUnlockedAppLock())
            await submitWrongPasswords(1, with: viewModel)
            return viewModel
        }
    }

    /// Only how long to wait, never how many attempts are left.
    @Test
    func changeWaiting() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .change, appLock: makeUnlockedAppLock())
            await submitWrongPasswords(5, with: viewModel)
            return viewModel
        }
    }

    @Test
    func changeDone() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .change, appLock: makeUnlockedAppLock())
            viewModel.currentPassword = Self.password
            viewModel.newPassword = "battery staple"
            viewModel.confirmation = "battery staple"
            await viewModel.submit()
            return viewModel
        }
    }

    @Test
    func turnOff() async throws {
        try await snapshotScenarios(dynamicTypeSizes: [.medium, .xxLarge]) {
            try await AppLockPasswordFormViewModel(purpose: .turnOff, appLock: makeUnlockedAppLock())
        }
    }

    /// Back after a wait started, it only says how long is left.
    @Test
    func turnOffWaiting() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .turnOff, appLock: makeUnlockedAppLock())
            await submitWrongPasswords(6, with: viewModel)
            return viewModel
        }
    }

    @Test
    func turnOffDone() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .turnOff, appLock: makeUnlockedAppLock())
            viewModel.currentPassword = Self.password
            await viewModel.submit()
            return viewModel
        }
    }
}

// MARK: - Helpers

extension AppLockPasswordSnapshotTests {
    private func makeAppLock(password: String?) throws -> AppLockService {
        try AppLockService(
            settings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            passwordService: FakeAppLockPasswordService(password: password),
            purgeSensitiveData: {},
        )
    }

    /// With the password set and the app unlocked, as it is in Settings.
    private func makeUnlockedAppLock() async throws -> AppLockService {
        let appLock = try makeAppLock(password: Self.password)
        await appLock.unlock()
        await appLock.unlock(password: Self.password)
        #expect(appLock.state == .unlocked)
        return appLock
    }

    private func submitWrongPasswords(_ count: Int, with viewModel: AppLockPasswordFormViewModel) async {
        for _ in 0 ..< count {
            viewModel.currentPassword = "wrong"
            viewModel.newPassword = "battery staple"
            viewModel.confirmation = "battery staple"
            await viewModel.submit()
        }
    }

    /// Snapshots the form in light and dark, with a view model made afresh for each: a form forgets what was typed
    /// into it when it goes.
    private func snapshotScenarios(
        dynamicTypeSizes: [DynamicTypeSize] = [.medium],
        lastBackup: VaultBackupEvent? = nil,
        testName: String = #function,
        makeViewModel: () async throws -> AppLockPasswordFormViewModel,
    ) async throws {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in dynamicTypeSizes {
                let view = try await AppLockPasswordFormView(
                    viewModel: makeViewModel(),
                    lastBackup: lastBackup,
                    close: {},
                )
                snapshot(view, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, testName: testName)
            }
        }
    }

    private func snapshot(
        _ view: some View,
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        testName: String = #function,
    ) {
        let framed = NavigationStack {
            view
        }
        .dynamicTypeSize(dynamicTypeSize)
        .framedForTest()

        assertSnapshot(
            of: framed,
            colorScheme: colorScheme,
            named: "\(colorScheme)_\(dynamicTypeSize)",
            testName: testName,
        )
    }
}
