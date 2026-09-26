import SwiftUI
import Toasts
import VaultFeed
import VaultiOSShared
import VaultSettings

/// Entrypoint scene for the vault app.
@MainActor
public struct VaultMainScene: Scene {
    @State private var pasteboard: Pasteboard = VaultRoot.pasteboard
    @State private var localSettings: LocalSettings = VaultRoot.localSettings
    @State private var deviceAuthenticationService = VaultRoot.deviceAuthenticationService
    @State private var appLockService = VaultRoot.appLockService
    @State private var vaultDataModel: VaultDataModel = VaultRoot.vaultDataModel
    @State private var injector: VaultInjector = VaultRoot.vaultInjector
    @State private var pendingOpenItemDetail: Identifier<VaultItem>?
    #if DEBUG
    @State private var isSeedingScreenshotVault = ScreenshotMode.isEnabled
    #endif

    public init() {
        // Don't wire auto-backup and widget reloads when the store failed
        // to open: the fallback store is empty, and backing it up would
        // replace a good backup with an empty vault.
        if VaultRoot.vaultStoreLoadFailureMessage == nil {
            VaultRoot.setup()
        }
    }

    public var body: some Scene {
        WindowGroup {
            if let failureMessage = VaultRoot.vaultStoreLoadFailureMessage {
                VaultStoreFailureView(message: failureMessage)
            } else {
                AppLockContainer(appLock: appLockService, localSettings: localSettings) {
                    #if DEBUG
                    if isSeedingScreenshotVault {
                        // Keeps the vault off screen until the demo data is in,
                        // so the navigation view's own setup sees the seeded vault.
                        Color.clear.task { await seedScreenshotVault() }
                    } else {
                        mainNavigationView
                    }
                    #else
                    mainNavigationView
                    #endif
                }
                // Out here to be heard while the app is locked: what a link
                // opens waits until the app is unlocked.
                .onOpenURL { url in
                    appLockService.performWhenUnlocked {
                        handle(url: url)
                    }
                }
            }
        }
    }

    private var mainNavigationView: some View {
        VaultMainNavigationView(
            pasteboard: pasteboard,
            localSettings: localSettings,
            deviceAuthenticationService: deviceAuthenticationService,
            vaultDataModel: vaultDataModel,
            injector: injector,
            pendingOpenItemDetail: $pendingOpenItemDetail,
            initialSelection: initialSelection,
        )
        .installToast(position: .top)
        .environment(appLockService)
        // Here rather than in the shared views, so the AutoFill extension doesn't show next codes.
        .environment(\.showsNextCode, localSettings.state.showsNextCode)
    }

    private var initialSelection: VaultMainNavigationView.SidebarItem {
        #if DEBUG
        if let scene = ScreenshotMode.scene {
            return scene.sidebarItem
        }
        #endif
        return .items
    }

    #if DEBUG
    private func seedScreenshotVault() async {
        do {
            let detailItemID = try await ScreenshotMode.seed(
                store: VaultRoot.vaultStore,
                dataModel: vaultDataModel,
                backupEventLogger: injector.backupEventLogger,
            )
            if ScreenshotMode.scene == .detail {
                pendingOpenItemDetail = detailItemID
            }
            isSeedingScreenshotVault = false
        } catch {
            fatalError("Unable to seed screenshot vault: \(error)")
        }
    }
    #endif

    private func handle(url: URL) {
        guard let action = WidgetDeepLink.parse(url) else { return }
        switch action {
        case let .incrementHOTP(itemID):
            // Widgets never offer this while the vault is encrypted, and a link left from before doesn't either.
            guard VaultRoot.isVaultPlain else { return }
            Task {
                try? await vaultDataModel.incrementCounter(id: .init(id: itemID))
            }
        case let .openItemDetail(itemID):
            pendingOpenItemDetail = .init(id: itemID)
        }
    }
}
