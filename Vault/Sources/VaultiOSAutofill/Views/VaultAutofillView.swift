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
                VaultAutofillCodeSelectorView(
                    localSettings: viewModel.localSettings,
                    viewGenerator: generator,
                    copyActionHandler: copyActionHandler,
                    textToInsertSubject: viewModel.textToInsertSubject,
                    cancelSubject: viewModel.cancelRequestSubject,
                )
            }
        case let .unimplemented(name):
            Text("Unimplemented \(name)")
        case nil:
            ProgressView()
        }
    }
}
