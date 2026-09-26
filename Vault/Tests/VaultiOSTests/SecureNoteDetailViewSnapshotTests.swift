import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
final class SecureNoteDetailViewSnapshotTests {
    @Test
    func emptyState() {
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "", contents: "", format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "",
                tags: [],
                visibility: .always,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: nil,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: false,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func lockedState() {
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "", contents: "", format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "",
                tags: [],
                visibility: .always,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .lockedWithNativeSecurity,
                color: nil,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: false,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func lockedStateNoAuthentication() {
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "", contents: "", format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "",
                tags: [],
                visibility: .always,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .lockedWithNativeSecurity,
                color: nil,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: false,
        )

        snapshotScenarios(view: sut, deviceAuthenticationPolicy: .cannotAuthenticate)
    }

    @Test
    func titleOnly() {
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "My Title", contents: "", format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "",
                tags: [],
                visibility: .always,
                searchableLevel: .none,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: nil,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: false,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func titleDescriptionAndShortContent() {
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "My Title", contents: "My contents", format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "My description",
                tags: [],
                visibility: .always,
                searchableLevel: .onlyTitle,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: nil,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: false,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func titleDescriptionAndLongContent() {
        let longContent = Array(repeating: "My content is cool.", count: 100).joined(separator: " ")
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "My Title", contents: longContent, format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "My description",
                tags: [],
                visibility: .always,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: .gray,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: false,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func contentUpdated() {
        let date = fixedTestDate()
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "My Title", contents: "My contents", format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: date,
                updated: date.addingTimeInterval(1), // different updated date
                relativeOrder: .min,
                userDescription: "My description",
                tags: [],
                visibility: .always,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: .black,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: false,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func editMode_emptyState() {
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "", contents: "", format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "",
                tags: [],
                visibility: .always,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: nil,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: true,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func editMode_editedContent() {
        let date = fixedTestDate()
        let sut = SecureNoteDetailView(
            editingExistingNote: .init(title: "My Title", contents: "My contents", format: .markdown),
            encryptionKey: nil,
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: date,
                updated: date.addingTimeInterval(1), // different updated date
                relativeOrder: .min,
                userDescription: "My description",
                tags: [],
                visibility: .always,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: .black,
                showInQuickType: false,
                previewMode: .titleAndFirstLine,
            ),
            editor: SecureNoteDetailEditorMock(),
            openInEditMode: true,
        )

        snapshotScenarios(view: sut)
    }
}

// MARK: - Helpers

extension SecureNoteDetailViewSnapshotTests {
    private func snapshotScenarios(
        view: some View,
        deviceAuthenticationPolicy: some DeviceAuthenticationPolicy = DeviceAuthenticationPolicyAlwaysAllow(),
        testName: String = #function,
    ) {
        let colorSchemes: [ColorScheme] = [.light, .dark]
        let dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge]
        for colorScheme in colorSchemes {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = view
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest(height: 1400)
                    .environment(DeviceAuthenticationService(policy: deviceAuthenticationPolicy))
                let named = "\(colorScheme)_\(dynamicTypeSize)"

                assertSnapshot(
                    of: snapshottingView,
                    colorScheme: colorScheme,
                    named: named,
                    testName: testName,
                )
            }
        }
    }

    private func fixedTestDate() -> Date {
        Date(timeIntervalSince1970: 40000)
    }
}
