import Foundation
import SwiftUI
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

    /// The iPhone Duo's inner screen, partly folded and held open like a book: the sidebar and the items beside it meet
    /// at the crease.
    @Test
    func layout_partlyFoldedLikeABook() throws {
        let localSettings = try LocalSettings(defaults: .nonPersistent())
        let pasteboard = Pasteboard(SystemPasteboardMock(), localSettings: localSettings)

        let view = VaultMainNavigationView(
            pasteboard: pasteboard,
            localSettings: localSettings,
            deviceAuthenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            vaultDataModel: anyVaultDataModel(),
            injector: anyVaultInjector(),
        )
        .environment(\.drawsGlassSnapshotBackdrop, true)
        .frame(width: PartlyFoldedScreen.book.size.width, height: PartlyFoldedScreen.book.size.height)
        .partlyFolded(.book)

        assertSnapshot(of: view, as: .image(traits: UITraitCollection(horizontalSizeClass: .regular)))
    }
}
