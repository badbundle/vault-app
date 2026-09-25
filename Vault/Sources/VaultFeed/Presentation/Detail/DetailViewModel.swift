import Combine
import Foundation

/// Common behaviours for the view model of an item's detail.
@MainActor
public protocol DetailViewModel: AnyObject, Observable {
    associatedtype Edits: EditableState
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

    func startEditing()
    func saveChanges() async
    func delete() async
    func done()
    func didEncounterErrorPublisher() -> AnyPublisher<any Error, Never>
    func isFinishedPublisher() -> AnyPublisher<Void, Never>
}

extension DetailViewModel {
    public var shouldShowDeleteButton: Bool {
        !isInitialCreation
    }

    public var allowsUnlockWithoutDeviceAuthentication: Bool {
        true
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
