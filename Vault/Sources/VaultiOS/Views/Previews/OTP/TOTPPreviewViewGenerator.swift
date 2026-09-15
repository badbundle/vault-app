import Combine
import CryptoEngine
import SwiftUI
import VaultFeed

/// An efficient generator of preview views for TOTP codes.
///
/// Internal caching and sharing of models and timers makes this very efficient.
@MainActor
public final class TOTPPreviewViewGenerator<Factory: TOTPPreviewViewFactory>: VaultItemPreviewViewGenerator {
    public typealias PreviewItem = TOTPAuthCode

    private let viewFactory: Factory
    private let repository: any TOTPPreviewViewRepository

    init(
        viewFactory: Factory,
        repository: any TOTPPreviewViewRepository,
    ) {
        self.viewFactory = viewFactory
        self.repository = repository
    }

    public func makeVaultPreviewView(
        item: PreviewItem,
        metadata: VaultItem.Metadata,
        behaviour: VaultItemViewBehaviour,
    ) -> some View {
        viewFactory.makeTOTPView(
            viewModel: repository.previewViewModel(metadata: metadata, code: item),
            periodState: repository.timerPeriodState(period: item.period),
            updater: repository.timerUpdater(period: item.period),
            behaviour: behaviour,
        )
    }

    public func clearViewCache() async {
        await repository.vaultItemCacheClearAll()
    }

    public func scenePhaseDidChange(to scene: ScenePhase) {
        switch scene {
        case .background, .inactive:
            repository.obfuscateForPrivacy()
            repository.stopAllTimers()
        case .active:
            // Unobfuscate before restarting so the codes reappear
            // immediately rather than waiting for the next timer tick.
            repository.unobfuscateForPrivacy()
            repository.restartAllTimers()
        @unknown default:
            break
        }
    }

    public func didAppear() {
        repository.restartAllTimers()
    }
}
