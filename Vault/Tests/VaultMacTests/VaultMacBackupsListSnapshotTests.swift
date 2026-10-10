import AppKit
import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import VaultKeygen
@testable import VaultMac

@MainActor
struct VaultMacBackupsListSnapshotTests {
    @Test(arguments: MacAppearance.allCases)
    func list(appearance: MacAppearance) throws {
        let view = try VaultMacBackupsList(selection: .constant(nil), services: Self.services(), now: Self.now)

        assertSnapshot(
            of: view,
            as: .macWindow(width: 320, height: 420, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    /// The open page's row is highlighted, as a Mac list's selected row is.
    @Test(arguments: MacAppearance.allCases)
    func pageSelected(appearance: MacAppearance) throws {
        let view = try VaultMacBackupsList(selection: .constant(.password), services: Self.services(), now: Self.now)

        assertSnapshot(
            of: view,
            as: .macWindow(width: 320, height: 420, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

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
