import Foundation
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
struct VaultMainNavigationViewSnapshotTests {
    @Test
    func layout() throws {
        let localSettings = try LocalSettings(defaults: .nonPersistent())
        let pasteboard = Pasteboard(SystemPasteboardMock(), localSettings: localSettings)
        let deviceAuthenticationService = DeviceAuthenticationService(policy: .alwaysAllow)
        let vaultDataModel = anyVaultDataModel()
        let injector = anyVaultInjector()

        let view = VaultMainNavigationView(
            pasteboard: pasteboard,
            localSettings: localSettings,
            deviceAuthenticationService: deviceAuthenticationService,
            vaultDataModel: vaultDataModel,
            injector: injector,
        )
        .environment(\.drawsGlassSnapshotBackdrop, true)
        .framedForTest()

        assertSnapshot(of: view, as: .image)
    }
}
