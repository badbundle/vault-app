import Combine
import Foundation
import SwiftUI
import VaultFeed

struct VaultDetailEditView<
    PreviewGenerator: VaultItemPreviewViewGenerator<VaultItem.Payload>,
>: View {
    var storedItem: VaultItem
    var previewGenerator: PreviewGenerator
    var copyActionHandler: any VaultItemCopyActionHandler
    var openInEditMode: Bool
    var openDetailSubject: PassthroughSubject<VaultItemEncryptionPayload, Never>
    var encryptionKey: DerivedEncryptionKey?
    @Binding var navigationPath: NavigationPath

    @Environment(VaultDataModel.self) private var dataModel
    @Environment(VaultInjector.self) private var injector
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        switch storedItem.item {
        case let .otpCode(code):
            OTPCodeDetailView(
                editingExistingCode: code,
                navigationPath: $navigationPath,
                dataModel: dataModel,
                storedMetadata: storedItem.metadata,
                editor: VaultDataModelEditorAdapter(
                    dataModel: dataModel,
                    keyDeriverFactory: injector.vaultKeyDeriverFactory,
                ),
                previewGenerator: previewGenerator,
                copyActionHandler: copyActionHandler,
                openInEditMode: openInEditMode,
                presentationMode: presentationMode,
            )
        case let .secureNote(note):
            SecureNoteDetailView(
                editingExistingNote: note,
                encryptionKey: encryptionKey,
                navigationPath: $navigationPath,
                dataModel: dataModel,
                storedMetadata: storedItem.metadata,
                editor: VaultDataModelEditorAdapter(
                    dataModel: dataModel,
                    keyDeriverFactory: injector.vaultKeyDeriverFactory,
                ),
                openInEditMode: openInEditMode,
            )
        case let .recoveryPhrase(phrase):
            // A decrypted recovery phrase always comes with the key it was decrypted with, which is needed to
            // re-encrypt it on save. Without one, there's no safe way to edit it.
            if let encryptionKey {
                RecoveryPhraseDetailView(
                    editingExisting: phrase,
                    encryptionKey: encryptionKey,
                    navigationPath: $navigationPath,
                    dataModel: dataModel,
                    storedMetadata: storedItem.metadata,
                    editor: VaultDataModelEditorAdapter(
                        dataModel: dataModel,
                        keyDeriverFactory: injector.vaultKeyDeriverFactory,
                    ),
                    openInEditMode: openInEditMode,
                )
            } else {
                Form {
                    PlaceholderView(
                        systemIcon: "exclamationmark.triangle.fill",
                        title: "Can't Open Item",
                        subtitle: "This item couldn't be opened. Close it and try again.",
                    )
                    .padding()
                    .containerRelativeFrame(.horizontal)
                }
            }
        case let .encryptedItem(item):
            EncryptedItemDetailView(
                viewModel: .init(
                    item: item,
                    metadata: storedItem.metadata,
                    keyDeriverFactory: injector.vaultKeyDeriverFactory,
                ),
                openDetailSubject: openDetailSubject,
                presentationMode: presentationMode,
            )
        }
    }
}
