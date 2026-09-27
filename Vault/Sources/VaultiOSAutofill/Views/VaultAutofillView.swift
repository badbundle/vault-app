import Foundation
import SwiftUI
import VaultFeed
import VaultiOS

struct VaultAutofillView<Generator: VaultItemPreviewViewGenerator<VaultItem.Payload>>: View {
    @State private var viewModel: VaultAutofillViewModel
    var generator: Generator
    var copyActionHandler: any VaultItemCopyActionHandler

    init(
        viewModel: VaultAutofillViewModel,
        copyActionHandler: any VaultItemCopyActionHandler,
        generator: Generator,
    ) {
        self.viewModel = viewModel
        self.generator = generator
        self.copyActionHandler = copyActionHandler
    }

    var body: some View {
        switch viewModel.feature {
        case .setupConfiguration:
            NavigationStack {
                VaultAutofillConfigurationView(viewModel: .init(
                    dismissSubject: viewModel
                        .configurationDismissSubject,
                ))
            }
        case .showAllCodesSelector:
            NavigationStack {
                switch viewModel.unlockAvailability {
                case .checking:
                    ProgressView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel", action: cancel)
                                    .tint(.red)
                            }
                        }
                case .available:
                    AppLockGate(appLock: viewModel.appLock, cancel: cancel) {
                        VaultAutofillCodeSelectorView(
                            localSettings: viewModel.localSettings,
                            viewGenerator: generator,
                            copyActionHandler: copyActionHandler,
                            textToInsertSubject: viewModel.textToInsertSubject,
                            cancelSubject: viewModel.cancelRequestSubject,
                        )
                    }
                case .needsTheApp(.notEnoughMemory):
                    AppLockOpenVaultView(reason: .notEnoughMemory, cancel: cancel)
                case .needsTheApp(.unavailable):
                    AppLockOpenVaultView(reason: .unavailableHere, cancel: cancel)
                }
            }
            .task(id: viewModel.preparation) {
                await viewModel.prepareToUnlock()
            }
        case let .unimplemented(name):
            Text("Unimplemented \(name)")
        case nil:
            ProgressView()
        }
    }

    private func cancel() {
        viewModel.cancelRequestSubject.send(.userCancelled)
    }
}
