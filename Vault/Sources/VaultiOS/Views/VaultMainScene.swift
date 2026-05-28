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
    @State private var vaultDataModel: VaultDataModel = VaultRoot.vaultDataModel
    @State private var injector: VaultInjector = VaultRoot.vaultInjector
    @State private var pendingOpenItemDetail: Identifier<VaultItem>?

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
                VaultMainNavigationView(
                    pasteboard: pasteboard,
                    localSettings: localSettings,
                    deviceAuthenticationService: deviceAuthenticationService,
                    vaultDataModel: vaultDataModel,
                    injector: injector,
                    pendingOpenItemDetail: $pendingOpenItemDetail,
                )
                .installToast(position: .top)
                .onOpenURL(perform: handle(url:))
            }
        }
    }

    private func handle(url: URL) {
        guard let action = WidgetDeepLink.parse(url) else { return }
        switch action {
        case let .incrementHOTP(itemID):
            Task {
                try? await vaultDataModel.incrementCounter(id: .init(id: itemID))
            }
        case let .openItemDetail(itemID):
            pendingOpenItemDetail = .init(id: itemID)
        }
    }
}
