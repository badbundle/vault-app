import Combine
import Foundation
import VaultCore
import VaultKeygen

@MainActor
@Observable
public final class PrivateKeyDetailViewModel: DetailViewModel {
    public var editingModel: DetailEditingModel<PrivateKeyDetailEdits>

    public enum Mode {
        case creating
        /// A private key is always encrypted, so there's always the key it was decrypted with.
        case editing(
            key: PrivateKey,
            metadata: VaultItem.Metadata,
            existingKey: DerivedEncryptionKey,
        )
    }

    private let mode: Mode
    /// Always starts locked for an existing item, whatever its stored lock state, and locks again whenever the app
    /// goes to the background.
    public var isLocked: Bool
    /// Even once unlocked, the key is masked until the user chooses to reveal it, so it isn't on screen the moment the
    /// item opens. Starts revealed only when creating, as there's nothing to hide yet.
    public var isKeyRevealed: Bool
    public var editorFlow: DetailEditorFlow
    public let dataModel: VaultDataModel
    private let detailEditState = DetailEditState<PrivateKeyDetailEdits>()
    private let didEncounterErrorSubject = PassthroughSubject<any Error, Never>()
    private let isFinishedSubject = PassthroughSubject<Void, Never>()
    private let editor: any PrivateKeyDetailEditor

    public init(
        mode: Mode,
        dataModel: VaultDataModel,
        editor: any PrivateKeyDetailEditor,
    ) {
        self.mode = mode
        self.dataModel = dataModel
        self.editor = editor
        isLocked = switch mode {
        case .creating: false
        case .editing: true
        }
        isKeyRevealed = switch mode {
        case .creating: true
        case .editing: false
        }
        editingModel = switch mode {
        case .creating:
            .init(detail: .new())
        case let .editing(key, metadata, encryptionKey):
            .init(detail: .init(
                title: key.title,
                contents: key.contents,
                key: key.key,
                color: metadata.color,
                viewConfig: .init(visibility: metadata.visibility, searchableLevel: metadata.searchableLevel),
                searchPassphrase: "",
                hasExistingSearchPassphrase: metadata.searchPassphrase != nil,
                killphraseEnabled: metadata.killphraseEnabled,
                newKillphrase: "",
                tags: metadata.tags,
                relativeOrder: metadata.relativeOrder,
                existingEncryptionKey: encryptionKey,
                previewMode: metadata.previewMode,
            ))
        }
        editorFlow = Self.makeEditorFlow(mode: mode)
    }

    private static func makeEditorFlow(mode: Mode) -> DetailEditorFlow {
        switch mode {
        case .creating: DetailEditorFlow(steps: DetailEditorStep.allCases, style: .guided)
        case .editing: DetailEditorFlow(steps: DetailEditorStep.allCases, style: .overview)
        }
    }

    /// Device authentication is required to see a private key, as for a recovery phrase: there's no way to skip the
    /// lock on a device without a passcode.
    ///
    /// Device authentication protects against an unattended device. It's the password, required to decrypt the item
    /// in the first place, that protects against someone coercing the user.
    public var allowsUnlockWithoutDeviceAuthentication: Bool {
        false
    }

    /// Lock the item, requiring authentication again to see it, and mask the key again. Called when the app moves to
    /// the background.
    public func lock() {
        isLocked = true
        isKeyRevealed = false
    }

    public var allTags: [VaultItemTag] {
        dataModel.allTags
    }

    /// Tags which haven't been added to this item yet.
    public var remainingTags: [VaultItemTag] {
        dataModel.allTags.filter { !editingModel.detail.tags.contains($0.id) }
    }

    public var tagsThatAreSelected: [VaultItemTag] {
        dataModel.allTags.filter { editingModel.detail.tags.contains($0.id) }
    }

    public var isInEditMode: Bool {
        detailEditState.isInEditMode
    }

    public var isSaving: Bool {
        detailEditState.isSaving
    }

    public var isInitialCreation: Bool {
        switch mode {
        case .creating: true
        case .editing: false
        }
    }

    public func startEditing() {
        detailEditState.startEditing()
        editorFlow = Self.makeEditorFlow(mode: mode)
    }

    /// Never includes the key or the description: the overview can be seen by anyone looking at the screen, and those
    /// are the secret parts. Only the kind of key it is.
    public func editorSummary(for step: DetailEditorStep) -> String {
        let detail = editingModel.detail
        let parts: [String] = switch step {
        case .content:
            [validationSummary().kindTitle]
        case .details:
            [visibleTitle]
        case .appearance:
            [editorTagsSummary(tagsThatAreSelected)]
        case .security:
            [detail.viewConfig.localizedTitle, detail.passwordState == .required ? "Password Required" : "Encrypted"]
        }
        return parts.filter(\.isNotBlank).joined(separator: " · ")
    }

    public func didEncounterErrorPublisher() -> AnyPublisher<any Error, Never> {
        didEncounterErrorSubject.eraseToAnyPublisher()
    }

    /// When we are done looking at the detail page and should submit.
    public func isFinishedPublisher() -> AnyPublisher<Void, Never> {
        isFinishedSubject.eraseToAnyPublisher()
    }

    public func saveChanges() async {
        do {
            try await detailEditState.saveChanges {
                switch mode {
                case .creating:
                    try await editor.createPrivateKey(initialEdits: editingModel.detail)
                    isFinishedSubject.send()
                case let .editing(_, metadata, _):
                    let key = try await editor.updatePrivateKey(id: metadata.id, edits: editingModel.detail)
                    // Keep the derived key rather than the password, so the plaintext password doesn't stay in
                    // memory and later saves don't need to derive the key again.
                    editingModel.detail.existingEncryptionKey = key
                    editingModel.detail.newEncryptionPassword = ""
                    editingModel.didPersist()
                }
            }
        } catch {
            didEncounterErrorSubject.send(error)
        }
    }

    public func delete() async {
        switch mode {
        case .creating:
            break // noop
        case let .editing(_, metadata, _):
            do {
                try await detailEditState.deleteItem {
                    try await editor.deletePrivateKey(id: metadata.id)
                } finished: {
                    isFinishedSubject.send()
                }
            } catch {
                didEncounterErrorSubject.send(error)
            }
        }
    }

    public func done() {
        detailEditState.exitCurrentModeClearingDirtyState {
            editingModel.restoreInitialState()
        } finished: {
            isFinishedSubject.send()
        }
    }
}

// MARK: - Titles

extension PrivateKeyDetailViewModel {
    @MainActor
    public struct Strings: DetailViewModelStrings {
        static let shared = Strings()
        private init() {}

        public let title = localized(key: "privateKeyDetail.title")
        public let deleteItemTitle = localized(key: "privateKeyDetail.action.delete.entity.title")
        public let deleteConfirmTitle = localized(key: "privateKeyDetail.action.delete.confirm.title")
        public let deleteConfirmSubtitle = localized(key: "privateKeyDetail.action.delete.confirm.subtitle")
        public let createdDateTitle = localized(key: "privateKeyDetail.listSection.created.title")
        public let updatedDateTitle = localized(key: "privateKeyDetail.listSection.updated.title")
        public let untitledTitle = localized(key: "privateKeyDetail.field.titleEmpty.title")
        public let doneEditingTitle = localized(key: "itemDetail.doneEditing.title")
        public let saveEditsTitle = localized(key: "itemDetail.saveEdits.title")
        public let cancelEditsTitle = localized(key: "itemDetail.cancelEdits.title")
        public let startEditingTitle = localized(key: "itemDetail.edit.title")
        public let visibilityTitle = localized(key: "itemDetail.visibility.title")
        public let passphraseSubtitle = localized(key: "itemDetail.passphrase.subtitle")
        public let killphraseSubtitle = localized(key: "itemDetail.killphrase.subtitle")
        public func tagCount(tags: Int) -> String {
            localized(key: "itemDetail.tagsCount.\(tags)")
        }
    }

    public var strings: Strings {
        Strings.shared
    }

    /// The title of the key, or a placeholder if it doesn't have one.
    public var visibleTitle: String {
        let title = editingModel.detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? strings.untitledTitle : title
    }

    /// The format the key is recognized as, and whether it's valid, for display.
    public func validationSummary() -> PrivateKeyValidationSummary {
        PrivateKeyValidationSummary(validation: editingModel.detail.validation)
    }

    public var createdDateValue: String? {
        switch mode {
        case let .editing(_, metadata, _):
            metadata.created.formatted(date: .abbreviated, time: .shortened)
        default:
            nil
        }
    }

    public var updatedDateValue: String? {
        switch mode {
        case let .editing(_, metadata, _) where metadata.updated > metadata.created.addingTimeInterval(5):
            metadata.updated.formatted(date: .abbreviated, time: .shortened)
        default:
            nil
        }
    }

    public var detailEntries: [DetailEntry] {
        var items = [DetailEntry]()
        if let createdDateValue {
            items.append(.init(title: strings.createdDateTitle, detail: createdDateValue, systemIconName: "clock"))
        }

        if let updatedDateValue {
            items.append(.init(
                title: strings.updatedDateTitle,
                detail: updatedDateValue,
                systemIconName: "clock.arrow.2.circlepath",
            ))
        }

        items.append(
            .init(
                title: strings.visibilityTitle,
                detail: editingModel.detail.viewConfig.localizedTitle,
                systemIconName: editingModel.detail.viewConfig.systemIconName,
            ),
        )

        return items
    }
}
