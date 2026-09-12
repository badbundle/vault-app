import Foundation
import SwiftUI
import VaultFeed

/// @mockable(typealias: PreviewView = AnyView; PreviewItem = VaultItem.Payload)
@MainActor
public protocol VaultItemPreviewViewGenerator<PreviewItem>: VaultItemPreviewSceneResponder {
    associatedtype PreviewItem
    associatedtype PreviewView: View
    func makeVaultPreviewView(item: PreviewItem, metadata: VaultItem.Metadata, behaviour: VaultItemViewBehaviour)
        -> PreviewView
    /// The view generator likely uses a cache to reduce the expensiveness of creating previews.
    /// This method clears that cache, so we can be sure that all views are generated from-scratch.
    func clearViewCache() async
}

/// A vault item that is able to respond to scene changes.
@MainActor
public protocol VaultItemPreviewSceneResponder {
    func scenePhaseDidChange(to scene: ScenePhase)
    func didAppear()
}
