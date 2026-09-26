import Foundation
import SwiftUI
import VaultFeed

/// The new-item sheet: choosing what kind of item to make, then making it, as the steps of one sheet.
///
/// Choosing a kind slides on to its editor's first step, and the sheet resizes to fit it just as it does between the
/// editor's steps. Back from that first step slides back to the choice. With Reduce Motion on, the screens fade.
///
/// The sheet sizes itself to the height each screen reports, rather than each screen sizing it, so it moves smoothly
/// from one screen's height to the next.
@MainActor
struct CreateItemFlowView<PreviewGenerator: VaultItemPreviewViewGenerator<VaultItem.Payload>>: View {
    var previewGenerator: PreviewGenerator
    var copyActionHandler: any VaultItemCopyActionHandler
    @Binding var navigationPath: NavigationPath

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flow: CreateItemFlow
    /// The kind of item on screen, or `nil` for the choice. Follows the flow a moment later, so the outgoing screen
    /// can take on the new direction before it leaves.
    @State private var displayedItem: CreatingItem?
    @State private var direction: DetailEditorFlow.Direction = .forward
    /// Identifies this sheet in the environment, which is the same for as long as it's open.
    @State private var sheetID = UUID()
    /// The height the screen being shown needs, once it's measured itself.
    @State private var sheetHeight: CGFloat?

    init(
        previewGenerator: PreviewGenerator,
        copyActionHandler: any VaultItemCopyActionHandler,
        navigationPath: Binding<NavigationPath>,
        flow: CreateItemFlow = .init(),
    ) {
        self.previewGenerator = previewGenerator
        self.copyActionHandler = copyActionHandler
        _navigationPath = navigationPath
        _flow = State(initialValue: flow)
        _displayedItem = State(initialValue: flow.creatingItem)
    }

    var body: some View {
        ZStack {
            if let displayedItem {
                VaultDetailCreateView(
                    creatingItem: displayedItem,
                    previewGenerator: previewGenerator,
                    copyActionHandler: copyActionHandler,
                    navigationPath: $navigationPath,
                )
                .environment(\.goBackFromFirstEditorStep, .init(id: sheetID) {
                    flow.goBackToItemTypes()
                })
                .environment(\.fittedSheetHeightReporter, heightReporter(for: displayedItem))
                .transition(transition)
            } else {
                CreateItemPickerView { item in
                    flow.choose(item)
                }
                .environment(\.fittedSheetHeightReporter, heightReporter(for: nil))
                .transition(transition)
            }
        }
        .animatedSheetHeight(sheetHeight)
        .onChange(of: flow) { _, newFlow in
            direction = newFlow.direction
            // A separate update, so the outgoing screen has already taken on the new direction when it leaves.
            Task { @MainActor in
                withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .snappy(duration: 0.4)) {
                    displayedItem = newFlow.creatingItem
                }
                // VoiceOver moves to the new screen, as it does between the editor's steps.
                AccessibilityNotification.ScreenChanged().post()
            }
        }
    }

    /// Where `screen` reports the height it needs: the sheet takes it if that's the screen the flow is on. The screen
    /// leaving can still report as it goes, which is ignored.
    private func heightReporter(for screen: CreatingItem?) -> FittedSheetHeightReporter {
        .init(id: sheetID) { height in
            guard screen == flow.creatingItem else { return }
            sheetHeight = height
        }
    }

    private var transition: AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            switch direction {
            case .forward: .push(from: .trailing)
            case .backward: .push(from: .leading)
            }
        }
    }
}
