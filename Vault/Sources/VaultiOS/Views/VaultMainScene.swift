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

    public init() {
        VaultRoot.setup()
    }

    public var body: some Scene {
        WindowGroup {
            VaultMainNavigationView(
                pasteboard: pasteboard,
                localSettings: localSettings,
                deviceAuthenticationService: deviceAuthenticationService,
                vaultDataModel: vaultDataModel,
                injector: injector,
            )
            .installToast(position: .top)
            .onOpenURL(perform: handle(url:))
        }
    }

    private func handle(url: URL) {
        guard let action = WidgetDeepLink.parse(url) else { return }
        switch action {
        case let .incrementHOTP(itemID):
            Task {
                try? await vaultDataModel.incrementCounter(id: .init(id: itemID))
            }
        }
    }
}
