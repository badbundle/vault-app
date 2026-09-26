import Combine
import Foundation

/// Common behaviours for the view model of an item's detail.
@MainActor
public protocol DetailViewModel: AnyObject, Observable {
    associatedtype Edits: DetailEditorEditableState
    associatedtype Strings: DetailViewModelStrings

    var editingModel: DetailEditingModel<Edits> { get set }
    var strings: Strings { get }
    var isInEditMode: Bool { get }
    var isInitialCreation: Bool { get }
    var isSaving: Bool { get }
    var isLocked: Bool { get set }
    /// If the item can be unlocked without device authentication, when the device has no passcode or biometrics set
    /// up. Defaults to `true`.
    var allowsUnlockWithoutDeviceAuthentication: Bool { get }
    /// Where the user is in the editor. Reset each time editing starts.
    var editorFlow: DetailEditorFlow { get set }

    func startEditing()
    func saveChanges() async
    func delete() async
    func done()
    func didEncounterErrorPublisher() -> AnyPublisher<any Error, Never>
    func isFinishedPublisher() -> AnyPublisher<Void, Never>
    /// A short description of what's set in `step`, for the editor's overview.
    func editorSummary(for step: DetailEditorStep) -> String
}

extension DetailViewModel {
    public var shouldShowDeleteButton: Bool {
        !isInitialCreation
    }

    public var allowsUnlockWithoutDeviceAuthentication: Bool {
        true
    }

    /// The attached tags for the editor's overview: their names, or that there aren't any.
    func editorTagsSummary(_ tags: [VaultItemTag]) -> String {
        tags.isEmpty ? "No Tags" : tags.map(\.name).joined(separator: ", ")
    }

    /// Whether the item is locked, for the editor's overview.
    func editorLockSummary(_ lockState: VaultItemLockState) -> String {
        lockState.isLocked ? "Locked" : "Not Locked"
    }
}

// MARK: - Editor

extension DetailViewModel {
    /// Whether the step being shown has everything it needs, so the editor can move on from it.
    public var canContinueInEditor: Bool {
        guard let step = editorFlow.currentStep else { return true }
        return editingModel.detail.isComplete(step)
    }

    public func isEditorStepComplete(_ step: DetailEditorStep) -> Bool {
        editingModel.detail.isComplete(step)
    }

    public func isEditorStepReachable(_ step: DetailEditorStep) -> Bool {
        editorFlow.isReachable(step, isComplete: editingModel.detail.isComplete)
    }

    /// Moves on to the next step, once the one being shown is complete.
    public func continueInEditor() {
        guard canContinueInEditor else { return }
        editorFlow.goForward()
    }

    /// Moves back to the previous step, or to the overview.
    public func goBackInEditor() {
        editorFlow.goBack()
    }

    /// Opens `step`, if it can be reached from where the editor is.
    public func showEditorStep(_ step: DetailEditorStep) {
        guard isEditorStepReachable(step) else { return }
        editorFlow.show(step)
    }
}

public protocol DetailViewModelStrings {
    var title: String { get }
    var cancelEditsTitle: String { get }
    var startEditingTitle: String { get }
    var saveEditsTitle: String { get }
    var doneEditingTitle: String { get }
    var deleteConfirmTitle: String { get }
    var deleteConfirmSubtitle: String { get }
    var deleteItemTitle: String { get }
}
