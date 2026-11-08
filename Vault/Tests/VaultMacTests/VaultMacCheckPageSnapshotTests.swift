import AppKit
import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import VaultKeygen
@testable import VaultMac

@MainActor
struct VaultMacCheckPageSnapshotTests {
    /// What the check does, and the button that chooses a backup.
    @Test(arguments: MacAppearance.allCases)
    func page(appearance: MacAppearance) throws {
        let view = try VaultMacCheckPage(services: Self.services())

        assertSnapshot(
            of: view,
            as: .macWindow(width: 560, height: 420, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    /// The backup opened: the page says so, and nothing about what's in it.
    @Test(arguments: MacAppearance.allCases)
    func opened(appearance: MacAppearance) throws {
        let viewModel = BackupCheckViewModel()
        viewModel.backupDidOpen()
        let view = try VaultMacCheckPage(services: Self.services(), viewModel: viewModel)

        assertSnapshot(
            of: view,
            as: .macWindow(width: 560, height: 420, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    private static func services() throws -> VaultMacBackupServices {
        let (dataModel, _) = try MacTestVault.make()
        let defaults = try Defaults(userDefaults: .nonPersistent())
        return VaultMacBackupServices(
            dataModel: dataModel,
            authentication: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            keyDeriverFactory: VaultKeyDeriverFactoryImpl(),
            clock: EpochClockMock(currentTime: 100),
            intervalTimer: IntervalTimerMock(),
            defaults: defaults,
            hintStorage: defaults,
            backupEventLogger: BackupEventLoggerMock(),
            autoBackupService: AutoBackupServiceMock(status: .disabled, configuration: .init()),
            encryptedVaultDecoder: EncryptedVaultDecoderImpl(),
        )
    }
}
