import Foundation
import SwiftUI
import VaultFeed

public struct VaultItemOnTapDecoratorViewGenerator<
    Generator: VaultItemPreviewViewGenerator,
>: VaultItemPreviewViewGenerator {
    public typealias PreviewItem = Generator.PreviewItem
    let generator: Generator
    let onTap: (Identifier<VaultItem>) async throws -> Void

    public init(generator: Generator, onTap: @escaping (Identifier<VaultItem>) async throws -> Void) {
        self.generator = generator
        self.onTap = onTap
    }

    public func makeVaultPreviewView(
        item: PreviewItem,
        metadata: VaultItem.Metadata,
        behaviour: VaultItemViewBehaviour,
    ) -> some View {
        Button {
            Task {
                // Fail closed. A thrown error means the tap action did not complete — most often a
                // failed authentication gating a copy — so the tap must do nothing at all.
                try? await onTap(metadata.id)
            }
        } label: {
            generator.makeVaultPreviewView(item: item, metadata: metadata, behaviour: behaviour)
        }
    }

    public func clearViewCache() async {
        await generator.clearViewCache()
    }

    public func scenePhaseDidChange(to scene: ScenePhase) {
        generator.scenePhaseDidChange(to: scene)
    }

    public func didAppear() {
        generator.didAppear()
    }
}

extension VaultItemOnTapDecoratorViewGenerator: VaultItemPreviewActionHandler
    where Generator: VaultItemPreviewActionHandler
{
    func previewActionForVaultItem(id: Identifier<VaultItem>) -> VaultItemPreviewAction? {
        generator.previewActionForVaultItem(id: id)
    }
}
