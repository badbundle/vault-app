import Combine
import Foundation
import SwiftUI
import VaultFeed
import VaultiOS
import VaultSettings

@MainActor
struct VaultAutofillCodeSelectorView<Generator: VaultItemPreviewViewGenerator<VaultItem.Payload>>: View {
    var localSettings: LocalSettings
    var viewGenerator: Generator
    let copyActionHandler: any VaultItemCopyActionHandler
    let textToInsertSubject: PassthroughSubject<String, Never>
    let cancelSubject: PassthroughSubject<VaultAutofillViewModel.RequestCancelReason, Never>

    @Environment(VaultDataModel.self) private var dataModel
    @Environment(DeviceAuthenticationService.self) var authenticationService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VaultItemFeedView(
            localSettings: localSettings,
            viewGenerator: interactableViewGenerator(),
            state: VaultItemFeedState(),
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    cancelSubject.send(.userCancelled)
                } label: {
                    Text("Cancel")
                }
                .tint(.red)
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            viewGenerator.scenePhaseDidChange(to: newValue)
        }
        .task {
            await prepareForDisplay()
        }
        .onAppear {
            viewGenerator.didAppear()
        }
    }

    /// Performs necessary actions before displaying to ensure that the displayed data is correct.
    private func prepareForDisplay() async {
        // First reload data, so we are sure the preview generator will create views based on fresh data.
        await dataModel.reloadData()
        // The view generator uses cached data. Force it to clear so we are sure fresh data is generated.
        // This is needed because data changes in-app may now be different that the data as seen by the extension.
        await viewGenerator.clearViewCache()
    }

    func interactableViewGenerator() -> VaultItemOnTapDecoratorViewGenerator<Generator> {
        VaultItemOnTapDecoratorViewGenerator(generator: viewGenerator) { id in
            guard let copyAction = copyActionHandler.textToCopyForVaultItem(id: id) else {
                // ignore
                return
            }

            if copyAction.requiresAuthenticationToCopy {
                // ignore, authenticated codes cannot be copied due to the authentication UI presenting behind
                // the autofill UI
                return
            }

            textToInsertSubject.send(copyAction.text)
        }
    }
}
