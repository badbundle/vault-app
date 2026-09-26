import Foundation
import SwiftUI
import VaultFeed

/// Gives each preview a menu, on touch and hold, of the actions `menuActions` offers for it. Also offered to
/// VoiceOver as actions.
///
/// A preview with no actions has no menu.
struct VaultItemMenuDecoratorViewGenerator<Generator: VaultItemPreviewViewGenerator>: VaultItemPreviewViewGenerator {
    typealias PreviewItem = Generator.PreviewItem
    let generator: Generator
    let menuActions: (Identifier<VaultItem>, VaultItemViewBehaviour) -> [VaultItemMenuAction]
    let perform: (VaultItemMenuAction, Identifier<VaultItem>) async throws -> Void

    func makeVaultPreviewView(
        item: PreviewItem,
        metadata: VaultItem.Metadata,
        behaviour: VaultItemViewBehaviour,
    ) -> some View {
        let actions = menuActions(metadata.id, behaviour)
        return generator.makeVaultPreviewView(item: item, metadata: metadata, behaviour: behaviour)
            .if(actions.isNotEmpty) { preview in
                preview
                    .contextMenu {
                        ForEach(actions, id: \.self) { action in
                            Button(action.title, systemImage: action.systemImage) {
                                run(action, on: metadata.id)
                            }
                        }
                    }
                    .accessibilityActions {
                        ForEach(actions, id: \.self) { action in
                            Button(action.title) {
                                run(action, on: metadata.id)
                            }
                        }
                    }
            }
    }

    private func run(_ action: VaultItemMenuAction, on id: Identifier<VaultItem>) {
        Task {
            // Fail closed, as a tap does: an error means authentication didn't happen, so nothing is copied.
            try? await perform(action, id)
        }
    }

    func clearViewCache() async {
        await generator.clearViewCache()
    }

    func scenePhaseDidChange(to scene: ScenePhase) {
        generator.scenePhaseDidChange(to: scene)
    }

    func didAppear() {
        generator.didAppear()
    }
}
