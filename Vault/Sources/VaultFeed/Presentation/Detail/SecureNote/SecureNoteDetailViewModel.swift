import Combine
import Foundation
import VaultCore
import VaultKeygen

@MainActor
@Observable
public final class SecureNoteDetailViewModel: DetailViewModel {
    public var editingModel: DetailEditingModel<SecureNoteDetailEdits>

    public enum Mode {
        /// A new note, starting from what `defaults` say.
        case creating(defaults: NewItemDefaults)
        case editing(
            note: SecureNote,
            metadata: VaultItem.Metadata,
            existingKey: DerivedEncryptionKey?,
        )
    }

    private let mode: Mode
    public var isLocked: Bool
    public var editorFlow: DetailEditorFlow
    public let dataModel: VaultDataModel
    private let detailEditState = DetailEditState<SecureNoteDetailEdits>()
    private let didEncounterErrorSubject = PassthroughSubject<any Error, Never>()
    private let isFinishedSubject = PassthroughSubject<Void, Never>()
    private let editor: any SecureNoteDetailEditor

    /// Create a view model for an existing note.
    public init(mode: Mode, dataModel: VaultDataModel, editor: any SecureNoteDetailEditor) {
        self.mode = mode
        self.dataModel = dataModel
        self.editor = editor
        isLocked = switch mode {
        case .creating: false
        case let .editing(_, metadata, _): metadata.lockState.isLocked
        }
        editingModel = switch mode {
        case let .creating(defaults):
            .init(detail: .new(defaults: defaults))
        case let .editing(note, metadata, encryptionKey):
            .init(detail: .init(
                contents: note.contents,
                textFormat: note.format,
                color: metadata.color,
                viewConfig: .init(visibility: metadata.visibility, searchableLevel: metadata.searchableLevel),
                searchPassphrase: "",
                hasExistingSearchPassphrase: metadata.searchPassphrase != nil,
                killphraseEnabled: metadata.killphraseEnabled,
                newKillphrase: "",
                tags: metadata.tags,
                lockState: metadata.lockState,
                relativeOrder: metadata.relativeOrder,
                existingEncryptionKey: encryptionKey,
                previewMode: metadata.previewMode,
            ))
        }
        editorFlow = Self.makeEditorFlow(mode: mode)
    }

    /// A note is named by its first line, so its editor has no details step.
    private static func makeEditorFlow(mode: Mode) -> DetailEditorFlow {
        let steps: [DetailEditorStep] = [.content, .appearance, .security]
        return switch mode {
        case .creating: DetailEditorFlow(steps: steps, style: .guided)
        case .editing: DetailEditorFlow(steps: steps, style: .overview)
        }
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

    public func editorSummary(for step: DetailEditorStep) -> String {
        let detail = editingModel.detail
        let parts: [String] = switch step {
        case .content:
            [
                detail.titleLine.isNotBlank ? detail.titleLine : strings.noteEmptyTitleTitle,
                detail.textFormat.localizedString,
            ]
        case .details:
            []
        case .appearance:
            [editorTagsSummary(tagsThatAreSelected)]
        case .security:
            [
                detail.viewConfig.localizedTitle,
                editorLockSummary(detail.lockState),
                detail.encrypted ? "Encrypted" : "",
            ]
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
                    try await editor.createNote(initialEdits: editingModel.detail)
                    isFinishedSubject.send()
                case let .editing(note, metadata, _):
                    try await editor.updateNote(id: metadata.id, item: note, edits: editingModel.detail)
                    // Locking takes effect on this very screen, so the user sees
                    // the lock work and has to unlock to get back in.
                    let didLock = !editingModel.initialDetail.lockState.isLocked && editingModel.detail.lockState
                        .isLocked
                    editingModel.didPersist()
                    if didLock {
                        isLocked = true
                    }
                }
            }
        } catch {
            didEncounterErrorSubject.send(error)
        }
    }

    public func delete() async {
        await deleteNote()
    }

    public func deleteNote() async {
        switch mode {
        case .creating:
            break // noop
        case let .editing(_, metadata, _):
            do {
                try await detailEditState.deleteItem {
                    try await editor.deleteNote(id: metadata.id)
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

extension SecureNoteDetailViewModel {
    @MainActor
    public struct Strings: DetailViewModelStrings {
        static let shared = Strings()
        private init() {}

        public let title = localized(key: "noteDetail.title")
        public let deleteItemTitle = localized(key: "noteDetail.action.delete.entity.title")
        public let deleteConfirmTitle = localized(key: "noteDetail.action.delete.confirm.title")
        public let deleteConfirmSubtitle = localized(key: "noteDetail.action.delete.confirm.subtitle")
        public let descriptionTitle = localized(key: "noteDetail.description.title")
        public let descriptionSubtitle = localized(key: "noteDetail.description.subtitle")
        public let createdDateTitle = localized(key: "noteDetail.listSection.created.title")
        public let updatedDateTitle = localized(key: "noteDetail.listSection.updated.title")
        public let doneEditingTitle = localized(key: "itemDetail.doneEditing.title")
        public let saveEditsTitle = localized(key: "itemDetail.saveEdits.title")
        public let cancelEditsTitle = localized(key: "itemDetail.cancelEdits.title")
        public let startEditingTitle = localized(key: "itemDetail.edit.title")
        public let noteTitle = localized(key: "noteDetail.field.noteTitle.title")
        public let noteTitleExample = localized(key: "noteDetail.field.noteTitle.example")
        public let noteDescription = localized(key: "noteDetail.field.noteDescription.title")
        public let noteContentsTitle = localized(key: "noteDetail.field.noteContents.title")
        public let noteEmptyTitleTitle = localized(key: "noteDetail.field.noteTitleEmpty.title")
        public let noteVisibilityTitle = localized(key: "itemDetail.visibilitySection.title")
        public let visibilityTitle = localized(key: "itemDetail.visibility.title")
        public let visibilitySubtitle = localized(key: "itemDetail.visibility.subtitle")
        public let passphraseTitle = localized(key: "itemDetail.passphrase.title")
        public let passphrasePrompt = localized(key: "itemDetail.passphrase.prompt")
        public let passphraseSubtitle = localized(key: "itemDetail.passphrase.subtitle")
        public let killphraseSubtitle = localized(key: "itemDetail.killphrase.subtitle")
        public func tagCount(tags: Int) -> String {
            localized(key: "itemDetail.tagsCount.\(tags)")
        }
    }

    public var strings: Strings {
        Strings.shared
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
