import Foundation
import SwiftUI
import VaultFeed

struct VaultDetailCreateView<
    PreviewGenerator: VaultItemPreviewViewGenerator<VaultItem.Payload>,
>: View {
    var creatingItem: CreatingItem
    var previewGenerator: PreviewGenerator
    var copyActionHandler: any VaultItemCopyActionHandler
    @Binding var navigationPath: NavigationPath
    @Environment(VaultDataModel.self) private var dataModel
    @Environment(VaultInjector.self) private var injector
    @Environment(DeviceAuthenticationService.self) private var authenticationService

    var body: some View {
        switch creatingItem {
        case .otpCode:
            OTPCodeCreateView(
                previewGenerator: previewGenerator,
                copyActionHandler: copyActionHandler,
                navigationPath: $navigationPath,
                intervalTimer: injector.intervalTimer,
            )
        case .secureNote:
            SecureNoteDetailView(
                newNoteWithEditor: VaultDataModelEditorAdapter(
                    dataModel: dataModel,
                    keyDeriverFactory: injector.vaultKeyDeriverFactory,
                ),
                navigationPath: $navigationPath,
                dataModel: dataModel,
            )
        case .recoveryPhrase:
            if authenticationService.canAuthenticate {
                RecoveryPhraseDetailView(
                    newPhraseWithEditor: VaultDataModelEditorAdapter(
                        dataModel: dataModel,
                        keyDeriverFactory: injector.vaultKeyDeriverFactory,
                    ),
                    navigationPath: $navigationPath,
                    dataModel: dataModel,
                )
            } else {
                RecoveryPhrasePasscodeRequiredView()
            }
        }
    }
}
