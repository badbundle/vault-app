import Combine
import Foundation
import VaultCore
import VaultKeygen

@MainActor
@Observable
public final class RecoveryPhraseDetailViewModel: DetailViewModel {
    public var editingModel: DetailEditingModel<RecoveryPhraseDetailEdits>

    public enum Mode {
        case creating
        /// A recovery phrase is always encrypted, so there's always the key it was decrypted with.
        case editing(
            phrase: RecoveryPhrase,
            metadata: VaultItem.Metadata,
            existingKey: DerivedEncryptionKey,
        )
    }

    private let mode: Mode
    /// Always starts locked for an existing item, whatever its stored lock state, and locks again whenever the app
    /// goes to the background.
    public var isLocked: Bool
    /// Even once unlocked, the words are masked until the user chooses to reveal them, so they aren't on screen the
    /// moment the item opens. Starts revealed only when creating, as there's nothing to hide yet.
    public var areWordsRevealed: Bool
    public let dataModel: VaultDataModel
    private let locale: Locale
    private let detailEditState = DetailEditState<RecoveryPhraseDetailEdits>()
    private let didEncounterErrorSubject = PassthroughSubject<any Error, Never>()
    private let isFinishedSubject = PassthroughSubject<Void, Never>()
    private let editor: any RecoveryPhraseDetailEditor

    public init(
        mode: Mode,
        dataModel: VaultDataModel,
        editor: any RecoveryPhraseDetailEditor,
        locale: Locale = .current,
    ) {
        self.mode = mode
        self.dataModel = dataModel
        self.editor = editor
        self.locale = locale
        isLocked = switch mode {
        case .creating: false
        case .editing: true
        }
        areWordsRevealed = switch mode {
        case .creating: true
        case .editing: false
        }
        editingModel = switch mode {
        case .creating:
            .init(detail: .new())
        case let .editing(phrase, metadata, encryptionKey):
            .init(detail: .init(
                title: phrase.title,
                contents: phrase.contents,
                standard: phrase.standard,
                words: phrase.words,
                seedPassphrase: phrase.passphrase,
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
    }

    /// Device authentication is required to see a recovery phrase: there's no way to skip the lock on a device
    /// without a passcode.
    ///
    /// Device authentication protects against an unattended device. It's the password, required to decrypt the item
    /// in the first place, that protects against someone coercing the user.
    public var allowsUnlockWithoutDeviceAuthentication: Bool {
        false
    }

    /// Lock the item, requiring authentication again to see it, and mask the words again. Called when the app moves
    /// to the background.
    public func lock() {
        isLocked = true
        areWordsRevealed = false
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
                    try await editor.createRecoveryPhrase(initialEdits: editingModel.detail)
                    isFinishedSubject.send()
                case let .editing(_, metadata, _):
                    let key = try await editor.updateRecoveryPhrase(id: metadata.id, edits: editingModel.detail)
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
                    try await editor.deleteRecoveryPhrase(id: metadata.id)
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

// MARK: - Suggestions

extension RecoveryPhraseDetailViewModel {
    /// Words from the wordlist that complete what's been entered for the word at `position`.
    ///
    /// Suggestions come from the first list, in order of preference, that has any: lists that contain all the other
    /// words entered so far, starting with the device's language.
    public func suggestions(forWordAt position: Int, limit: Int = 3) -> [String] {
        let words = editingModel.detail.words
        guard words.indices.contains(position) else { return [] }
        let prefix = words[position].trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefix.isNotEmpty else { return [] }

        let otherWords = words.enumerated().filter { $0.offset != position && $0.element.isNotBlank }.map(\.element)
        let wordlists = candidateWordlists().compactMap(RecoveryPhraseWordlist.named)
        let matchingOtherWords = wordlists.filter { list in otherWords.allSatisfy(list.contains) }
        for wordlist in matchingOtherWords.isEmpty ? wordlists : matchingOtherWords {
            let completions = wordlist.completions(forPrefix: prefix, limit: limit)
            guard completions.isNotEmpty else { continue }
            // No need to suggest the word that's already been entered.
            return completions == [prefix] ? [] : completions
        }
        return []
    }

    private func candidateWordlists() -> [RecoveryPhraseWordlist.ID] {
        switch editingModel.detail.standard {
        case .bip39:
            preferringDeviceLanguage(BIP39Language.allCases).map { .bip39($0) }
        case .electrum:
            preferringDeviceLanguage([.english, .spanish, .japanese, .portuguese, .chineseSimplified])
                .map { .bip39($0) }
        case .slip39: [.slip39]
        case .monero: [.monero]
        case .other: []
        }
    }

    private func preferringDeviceLanguage(_ languages: [BIP39Language]) -> [BIP39Language] {
        let deviceLanguage = languages.first { language in
            let identifier = Locale.Language(identifier: language.localeIdentifier)
            return identifier.languageCode == locale.language.languageCode
                && (identifier.script == nil || identifier.script == locale.language.script)
        }
        guard let deviceLanguage else { return languages }
        return [deviceLanguage] + languages.filter { $0 != deviceLanguage }
    }
}

// MARK: - Titles

extension RecoveryPhraseDetailViewModel {
    @MainActor
    public struct Strings: DetailViewModelStrings {
        static let shared = Strings()
        private init() {}

        public let title = localized(key: "recoveryPhraseDetail.title")
        public let deleteItemTitle = localized(key: "recoveryPhraseDetail.action.delete.entity.title")
        public let deleteConfirmTitle = localized(key: "recoveryPhraseDetail.action.delete.confirm.title")
        public let deleteConfirmSubtitle = localized(key: "recoveryPhraseDetail.action.delete.confirm.subtitle")
        public let createdDateTitle = localized(key: "recoveryPhraseDetail.listSection.created.title")
        public let updatedDateTitle = localized(key: "recoveryPhraseDetail.listSection.updated.title")
        public let untitledTitle = localized(key: "recoveryPhraseDetail.field.titleEmpty.title")
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

        public func wordNumber(_ number: Int) -> String {
            localized(key: "recoveryPhraseDetail.word.\(number)")
        }
    }

    public var strings: Strings {
        Strings.shared
    }

    /// The title of the phrase, or a placeholder if it doesn't have one.
    public var visibleTitle: String {
        let title = editingModel.detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? strings.untitledTitle : title
    }

    /// A summary of whether the phrase is valid, for display.
    ///
    /// - Parameter position: The word currently being typed, if any. It isn't reported as unknown, as it's likely
    ///   just incomplete.
    public func validationSummary(whileEditingWordAt position: Int? = nil) -> RecoveryPhraseValidationSummary {
        let detail = editingModel.detail
        var validation = detail.validation
        if let position, validation.unknownWordPositions.contains(position) {
            var words = detail.words
            words[position] = ""
            validation = RecoveryPhraseValidator.validate(words: words, standard: detail.standard)
        }
        return RecoveryPhraseValidationSummary(
            validation: validation,
            standard: detail.standard,
            wordCount: detail.wordCount,
        )
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
