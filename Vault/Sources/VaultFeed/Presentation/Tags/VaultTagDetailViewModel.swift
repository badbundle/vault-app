import Foundation
import FoundationExtensions
import VaultCore

@MainActor
@Observable
public final class VaultTagDetailViewModel {
    public let strings = VaultTagDetailViewModelStrings()
    private let existingTag: VaultItemTag.Write
    public var currentTag: VaultItemTag.Write
    public internal(set) var saveError: PresentationError?
    public internal(set) var deleteError: PresentationError?

    private let tagId: Identifier<VaultItemTag>?
    /// Stands in for the identifier of a tag that hasn't been saved yet.
    private let unsavedTagId = Identifier<VaultItemTag>()
    private let dataModel: VaultDataModel

    public static var defaultIconOption: String {
        VaultItemTag.defaultIconName
    }

    public static var systemIconOptions: [String] {
        [
            "tag.fill", // VaultItemTag.defaultIconName
            "briefcase.fill",
            "tree.fill",
            "mountain.2.fill",
            "dog.fill",
            "cat.fill",
            "tortoise.fill",
            "bird.fill",
            "fish.fill",
            "carrot.fill",
            "clock.fill",
            "person.fill",
            "person.2.fill",
            "person.3.fill",
            "figure.stand",
            "figure.walk",
            "figure.mixed.cardio",
            "figure.play",
            "figure.fall",
            "figure.and.child.holdinghands",
            "figure.2.and.child.holdinghands",
            "figure.2.arms.open",
            "star.fill",
            "heart.fill",
            "flag.fill",
            "flag.2.crossed.fill",
            "figure.child.and.lock.open.fill",
            "bell.fill",
            "book.fill",
            "folder.fill",
            "paperplane.fill",
            "dumbbell.fill",
            "football.fill",
            "tennisball.fill",
            "gym.bag.fill",
            "gamecontroller.fill",
            "flag.checkered",
            "pencil",
            "scissors",
            "doc.text.fill",
            "doc.plaintext.fill",
            "doc.richtext.fill",
            "doc.on.doc.fill",
            "doc.on.clipboard.fill",
            "sun.max.fill",
            "moon.fill",
            "cloud.fill",
            "cloud.sun.fill",
            "drop.fill",
            "bolt.fill",
            "flame.fill",
        ]
    }

    public init(dataModel: VaultDataModel, existingTag: VaultItemTag?) {
        self.dataModel = dataModel
        self.existingTag = if let existingTag {
            existingTag.makeWritable()
        } else {
            .new()
        }
        currentTag = self.existingTag
        tagId = existingTag?.id
    }

    public var isNew: Bool {
        tagId == nil
    }

    public var isDirty: Bool {
        existingTag != currentTag
    }

    public var isExistingItem: Bool {
        tagId != nil
    }

    public var systemIconOptions: [String] {
        Self.systemIconOptions
    }

    /// The tag as it stands with the current edits, for previewing how it
    /// will look once saved.
    public var previewTag: VaultItemTag {
        VaultItemTag(
            id: tagId ?? unsavedTagId,
            name: currentTag.name,
            color: currentTag.color,
            iconName: currentTag.iconName,
        )
    }

    private func makeWritableTag() -> VaultItemTag.Write {
        currentTag
    }

    public var isValidToSave: Bool {
        currentTag.name.isNotBlank
    }

    public func save() async {
        do {
            if let tagId {
                try await dataModel.update(tagID: tagId, data: makeWritableTag())
            } else {
                try await dataModel.insert(tag: makeWritableTag())
            }
        } catch {
            saveError = .init(
                userTitle: strings.saveErrorTitle,
                userDescription: strings.genericErrorDetail,
                debugDescription: error.localizedDescription,
            )
        }
    }

    /// Delete the current tag, if there is a current tag.
    public func delete() async {
        do {
            guard let tagId else { return }
            try await dataModel.delete(tagID: tagId)
        } catch {
            deleteError = .init(
                userTitle: strings.deleteErrorTitle,
                userDescription: strings.genericErrorDetail,
                debugDescription: error.localizedDescription,
            )
        }
    }

    /// Removes any error messages that are currently displaying.
    public func clearErrors() {
        saveError = nil
        deleteError = nil
    }
}

// MARK: - Strings

public struct VaultTagDetailViewModelStrings: Sendable {
    fileprivate init() {}

    public let title = localized(key: "tagDetail.title")
    public let deleteConfirmTitle = localized(key: "tagDetail.action.delete.confirm.title")
    public let deleteConfirmSubtitle = localized(key: "tagDetail.action.delete.confirm.subtitle")
    public let deleteItemTitle = localized(key: "tagDetail.action.delete.entity.title")
    public let saveErrorTitle = localized(key: "tagDetail.saveError.title")
    public let deleteErrorTitle = localized(key: "tagDetail.deleteError.title")
    public let genericErrorDetail = localized(key: "tagDetail.genericError.detail")
}
