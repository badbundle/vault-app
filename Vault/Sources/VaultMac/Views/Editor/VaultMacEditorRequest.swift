import SwiftUI
import VaultCore
import VaultFeed
import VaultSettings

/// What an editor sheet is open for: a new item of a kind, or an existing one, decrypted if it's encrypted.
enum VaultMacEditorRequest: Identifiable {
    case newCode
    case newNote
    case newRecoveryPhrase
    case editCode(OTPAuthCode, VaultItem.Metadata)
    case editNote(SecureNote, VaultItem.Metadata, DerivedEncryptionKey?)
    case editRecoveryPhrase(RecoveryPhrase, VaultItem.Metadata, DerivedEncryptionKey)

    var id: String {
        switch self {
        case .newCode: "new-code"
        case .newNote: "new-note"
        case .newRecoveryPhrase: "new-recovery-phrase"
        case let .editCode(_, metadata),
             let .editNote(_, metadata, _),
             let .editRecoveryPhrase(_, metadata, _):
            metadata.id.id.uuidString
        }
    }
}

/// Opens an editor sheet: the main window's, for an item's page or the New Item menu.
@MainActor
struct VaultMacEditAction {
    var perform: @MainActor (VaultMacEditorRequest) -> Void

    func callAsFunction(_ request: VaultMacEditorRequest) {
        perform(request)
    }
}

extension EnvironmentValues {
    @Entry var vaultMacEdit: VaultMacEditAction?
}

extension FocusedValues {
    /// Opens a new item's editor: New Code (⌘N), New Note and New Recovery Phrase.
    @Entry var vaultMacNewItemAction: VaultMacEditAction?
}

/// The editor sheet for a request, on the shared editors' view models.
struct VaultMacEditorSheet: View {
    var request: VaultMacEditorRequest
    var dataModel: VaultDataModel
    var keyDeriverFactory: any VaultKeyDeriverFactory
    var localSettings: LocalSettings
    var close: () -> Void

    var body: some View {
        let adapter = VaultDataModelEditorAdapter(dataModel: dataModel, keyDeriverFactory: keyDeriverFactory)
        let defaults = NewItemDefaults(
            lockNewItems: localSettings.state.lockNewItems,
            showNewCodesInQuickType: localSettings.state.showNewCodesInQuickType,
        )
        switch request {
        case .newCode:
            VaultMacCodeEditor(
                viewModel: .init(mode: .creating(defaults: defaults), dataModel: dataModel, editor: adapter),
                close: close,
            )
        case let .editCode(code, metadata):
            VaultMacCodeEditor(
                viewModel: .init(mode: .editing(code: code, metadata: metadata), dataModel: dataModel, editor: adapter),
                close: close,
            )
        case .newNote:
            VaultMacNoteEditor(
                viewModel: .init(mode: .creating(defaults: defaults), dataModel: dataModel, editor: adapter),
                close: close,
            )
        case let .editNote(note, metadata, key):
            VaultMacNoteEditor(
                viewModel: .init(
                    mode: .editing(note: note, metadata: metadata, existingKey: key),
                    dataModel: dataModel,
                    editor: adapter,
                ),
                close: close,
            )
        case .newRecoveryPhrase:
            VaultMacRecoveryPhraseEditor(
                viewModel: .init(mode: .creating, dataModel: dataModel, editor: adapter),
                close: close,
            )
        case let .editRecoveryPhrase(phrase, metadata, key):
            VaultMacRecoveryPhraseEditor(
                viewModel: .init(
                    mode: .editing(phrase: phrase, metadata: metadata, existingKey: key),
                    dataModel: dataModel,
                    editor: adapter,
                ),
                close: close,
            )
        }
    }
}

/// The open item's Edit and Delete buttons, on its page. While its page shows it, they're the Item menu's Edit Item
/// (⌘E) and Delete Item (⌘⌫) too, so neither works on an item whose page is locked.
struct VaultMacItemPageButtons: View {
    var request: VaultMacEditorRequest
    var metadata: VaultItem.Metadata
    @Environment(\.vaultMacEdit) private var edit
    @Environment(\.vaultMacDelete) private var delete

    var body: some View {
        HStack {
            Button("Edit") {
                edit?(request)
            }
            .disabled(edit == nil)
            .accessibilityIdentifier("detail.edit")
        }
        .focusedSceneValue(\.vaultMacItemActions, actions)
    }

    private var actions: VaultMacItemMenuActions? {
        guard let edit, let delete else { return nil }
        return VaultMacItemMenuActions(
            edit: VaultMacMenuAction { edit(request) },
            delete: VaultMacMenuAction { delete(metadata) },
        )
    }
}

/// What the Item menu does to the open item.
@MainActor
struct VaultMacItemMenuActions {
    var edit: VaultMacMenuAction
    var delete: VaultMacMenuAction
}

/// Asks whether to delete an item, then deletes it: the main window's, for the Item menu.
@MainActor
struct VaultMacDeleteAction {
    var perform: @MainActor (VaultItem.Metadata) -> Void

    func callAsFunction(_ metadata: VaultItem.Metadata) {
        perform(metadata)
    }
}

extension EnvironmentValues {
    @Entry var vaultMacDelete: VaultMacDeleteAction?
}

extension FocusedValues {
    /// Edit Item and Delete Item, for the item whose page shows it.
    @Entry var vaultMacItemActions: VaultMacItemMenuActions?
}
