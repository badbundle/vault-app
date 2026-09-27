import Foundation
import SwiftUI
import VaultFeed
import VaultiOS

struct VaultAutofillView<Generator: VaultItemPreviewViewGenerator<VaultItem.Payload>>: View {
    @State private var viewModel: VaultAutofillViewModel
    var generator: Generator
    var copyActionHandler: any VaultItemCopyActionHandler
    @Environment(\.scenePhase) private var scenePhase

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
                        if viewModel.isVaultReady {
                            VaultAutofillCodeSelectorView(
                                localSettings: viewModel.localSettings,
                                viewGenerator: generator,
                                copyActionHandler: copyActionHandler,
                                textToInsertSubject: viewModel.textToInsertSubject,
                                cancelSubject: viewModel.cancelRequestSubject,
                            )
                        } else {
                            // Only once the sheet's lock is unlocked: the vault's checked, and opened with the device
                            // key, now. Again after every lock.
                            ProgressView()
                                .task(id: viewModel.lockCount) {
                                    await viewModel.getVaultReadyToShow()
                                }
                        }
                    }
                case .needsTheApp(.notEnoughMemory):
                    AppLockOpenVaultView(reason: .notEnoughMemory, cancel: cancel)
                case .needsTheApp(.unavailable):
                    AppLockOpenVaultView(reason: .unavailableHere, cancel: cancel)
                }
            }
            .task {
                await viewModel.prepareToUnlock()
            }
            .onChange(of: scenePhase) { _, phase in
                viewModel.scenePhaseDidChange(to: phase)
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
