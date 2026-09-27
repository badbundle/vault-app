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
    private static let duressPassword = "plausible decoy"

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

    /// Nothing on it depends on whether a duress vault was made, or is open: it matches `manage`'s references.
    @Test
    func manage_isTheSameWithADuressVaultAndInOne() async throws {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.medium, .xxLarge] {
                for appLock in try await [makeUnlockedAppLockWithDuressVault(), makeAppLockInDuressVault()] {
                    let view = AppLockPasswordManageView(close: {})
                        .environment(appLock)
                    snapshot(view, colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize, testName: "manage()")
                }
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

    // MARK: - Duress password

    @Test
    func setDuress() async throws {
        try await snapshotScenarios(dynamicTypeSizes: [.medium, .xxLarge]) {
            try await AppLockPasswordFormViewModel(purpose: .setDuress, appLock: makeUnlockedAppLock())
        }
    }

    /// Too short, with a confirmation that doesn't match, so it can't be submitted.
    @Test
    func setDuressTooShort() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .setDuress, appLock: makeUnlockedAppLock())
            viewModel.newPassword = "decoy"
            viewModel.confirmation = "decoy!"
            return viewModel
        }
    }

    @Test
    func setDuressOnlyNumbers() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .setDuress, appLock: makeUnlockedAppLock())
            viewModel.newPassword = "12345678"
            viewModel.confirmation = "12345678"
            return viewModel
        }
    }

    /// The App Lock Password, refused by the password service.
    @Test
    func setDuressRefused() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .setDuress, appLock: makeUnlockedAppLock())
            await submitDuressPassword(Self.password, with: viewModel)
            return viewModel
        }
    }

    @Test
    func setDuressFailed() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let appLock = try await makeUnlockedAppLock(service: service)
        service.failure = TestError()

        try await snapshotScenarios {
            let viewModel = AppLockPasswordFormViewModel(purpose: .setDuress, appLock: appLock)
            await submitDuressPassword(Self.duressPassword, with: viewModel)
            return viewModel
        }
    }

    @Test
    func setDuressDone() async throws {
        try await snapshotScenarios {
            let viewModel = try await AppLockPasswordFormViewModel(purpose: .setDuress, appLock: makeUnlockedAppLock())
            await submitDuressPassword(Self.duressPassword, with: viewModel)
            return viewModel
        }
    }

    /// With a duress vault already made, and inside one, the screen and its confirmation match the references made
    /// without one.
    @Test
    func setDuress_isTheSameWithADuressVaultAndInOne() async throws {
        for makeAppLock in [makeUnlockedAppLockWithDuressVault, makeAppLockInDuressVault] {
            try await snapshotScenarios(dynamicTypeSizes: [.medium, .xxLarge], testName: "setDuress()") {
                try await AppLockPasswordFormViewModel(purpose: .setDuress, appLock: makeAppLock())
            }
            try await snapshotScenarios(testName: "setDuressDone()") {
                let viewModel = try await AppLockPasswordFormViewModel(purpose: .setDuress, appLock: makeAppLock())
                await submitDuressPassword("nested decoy", with: viewModel)
                return viewModel
            }
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
    private func makeUnlockedAppLock(
        service: FakeAppLockPasswordService = FakeAppLockPasswordService(password: Self.password),
        unlockingWith password: String = Self.password,
    ) async throws -> AppLockService {
        let appLock = try AppLockService(
            settings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            passwordService: service,
            purgeSensitiveData: {},
        )
        await appLock.unlock()
        await appLock.unlock(password: password)
        #expect(appLock.state == .unlocked)
        return appLock
    }

    /// Unlocked into the real vault, which has made a duress vault.
    private func makeUnlockedAppLockWithDuressVault() async throws -> AppLockService {
        let service = FakeAppLockPasswordService(password: Self.password)
        try await service.makeDuressVault(password: Self.duressPassword)
        return try await makeUnlockedAppLock(service: service)
    }

    /// Unlocked into a duress vault, with its password.
    private func makeAppLockInDuressVault() async throws -> AppLockService {
        let service = FakeAppLockPasswordService(password: Self.password)
        try await service.makeDuressVault(password: Self.duressPassword)
        return try await makeUnlockedAppLock(service: service, unlockingWith: Self.duressPassword)
    }

    private func submitDuressPassword(_ password: String, with viewModel: AppLockPasswordFormViewModel) async {
        viewModel.newPassword = password
        viewModel.confirmation = password
        await viewModel.submit()
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
