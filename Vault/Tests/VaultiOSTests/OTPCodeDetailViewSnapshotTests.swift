import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
final class OTPCodeDetailViewSnapshotTests {
    @Test
    func emptyState() {
        let sut = OTPCodeDetailView(
            editingExistingCode: .init(type: .totp(period: 30), data: .init(secret: .empty(), accountName: "")),
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
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            editor: OTPCodeDetailEditorMock(),
            previewGenerator: makeCodePreviewGenerator(),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            openInEditMode: false,
            presentationMode: .none,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func lockedState() {
        let sut = OTPCodeDetailView(
            editingExistingCode: .init(type: .totp(period: 30), data: .init(secret: .empty(), accountName: "")),
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
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            editor: OTPCodeDetailEditorMock(),
            previewGenerator: makeCodePreviewGenerator(),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            openInEditMode: false,
            presentationMode: .none,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func lockedStateNoAuthentication() {
        let sut = OTPCodeDetailView(
            editingExistingCode: .init(type: .totp(period: 30), data: .init(secret: .empty(), accountName: "")),
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
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            editor: OTPCodeDetailEditorMock(),
            previewGenerator: makeCodePreviewGenerator(),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            openInEditMode: false,
            presentationMode: .none,
        )

        snapshotScenarios(view: sut, deviceAuthenticationPolicy: .cannotAuthenticate)
    }

    @Test
    func withUserDescription() {
        let sut = OTPCodeDetailView(
            editingExistingCode: .init(type: .totp(period: 30), data: .init(secret: .empty(), accountName: "")),
            navigationPath: .constant(NavigationPath()),
            dataModel: anyVaultDataModel(),
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "This is my description",
                tags: [],
                visibility: .onlySearch,
                searchableLevel: .onlyTitle,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: nil,
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            editor: OTPCodeDetailEditorMock(),
            previewGenerator: makeCodePreviewGenerator(),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            openInEditMode: false,
            presentationMode: .none,
        )

        snapshotScenarios(view: sut)
    }

    /// Near the end of the countdown, with Show Next Code on, the next code shows above the bar.
    @Test
    func nextCodeShowing() {
        let sut = OTPCodeDetailView(
            editingExistingCode: .init(type: .totp(period: 30), data: .init(secret: .empty(), accountName: "")),
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
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            editor: OTPCodeDetailEditorMock(),
            previewGenerator: makeCodePreviewGenerator(nextCode: "654321"),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            openInEditMode: false,
            presentationMode: .none,
        )
        .environment(\.showsNextCode, true)

        snapshotScenarios(view: sut)
    }

    @Test
    func editMode_emptyState() {
        let sut = OTPCodeDetailView(
            editingExistingCode: .init(type: .totp(period: 30), data: .init(secret: .empty(), accountName: "")),
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
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            editor: OTPCodeDetailEditorMock(),
            previewGenerator: makeCodePreviewGenerator(),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            openInEditMode: true,
            presentationMode: .none,
        )

        snapshotScenarios(view: sut)
    }

    /// A counter-based code, with its refresh button beside the bar.
    @Test
    func hotpCode() {
        let sut = OTPCodeDetailView(
            editingExistingCode: .init(
                type: .hotp(counter: 3),
                data: .init(secret: .empty(), accountName: "bmackey", issuer: "Legacy VPN"),
            ),
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
                color: .init(red: 0.45, green: 0.45, blue: 0.5),
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            editor: OTPCodeDetailEditorMock(),
            previewGenerator: makeCodePreviewGenerator(isHOTP: true),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            openInEditMode: false,
            presentationMode: .none,
        )

        snapshotScenarios(view: sut)
    }

    @Test
    func withTags() async {
        let sut = await makeSUTWithTags(openInEditMode: false)

        snapshotScenarios(view: sut)
    }

    @Test
    func editMode_withTags() async {
        let sut = await makeSUTWithTags(openInEditMode: true)

        snapshotScenarios(view: sut)
    }
}

// MARK: - Helpers

extension OTPCodeDetailViewSnapshotTests {
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
                    .framedForTest()
                    .environment(makePasteboard())
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

    /// A code with enough tags attached that they wrap onto a second line.
    private func makeSUTWithTags(openInEditMode: Bool) async -> some View {
        let tags = [
            anyVaultItemTag(name: "Work", color: .tagDefault, iconName: "briefcase.fill"),
            anyVaultItemTag(name: "Personal", color: .init(red: 0.2, green: 0.72, blue: 0.45), iconName: "person.fill"),
            anyVaultItemTag(
                name: "Finance",
                color: .init(red: 0.96, green: 0.58, blue: 0.16),
                iconName: "creditcard.fill",
            ),
            anyVaultItemTag(name: "Travel", color: .init(red: 0.62, green: 0.4, blue: 0.93), iconName: "airplane"),
        ]
        let tagStore = VaultTagStoreStub()
        tagStore.retrieveTagsHandler = { tags }
        let dataModel = anyVaultDataModel(vaultTagStore: tagStore)
        await dataModel.reloadTags()

        return OTPCodeDetailView(
            editingExistingCode: .init(type: .totp(period: 30), data: .init(secret: .empty(), accountName: "")),
            navigationPath: .constant(NavigationPath()),
            dataModel: dataModel,
            storedMetadata: .init(
                id: .new(),
                created: fixedTestDate(),
                updated: fixedTestDate(),
                relativeOrder: .min,
                userDescription: "",
                tags: Set(tags.map(\.id)),
                visibility: .always,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: .notLocked,
                color: nil,
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            editor: OTPCodeDetailEditorMock(),
            previewGenerator: makeCodePreviewGenerator(),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            openInEditMode: openInEditMode,
            presentationMode: .none,
        )
    }

    /// Draws a code's preview as the app does, with a fixed code and, for a TOTP code, a countdown partway through.
    ///
    /// - Parameter nextCode: The next code, as though the countdown is near its end.
    private func makeCodePreviewGenerator(
        isHOTP: Bool = false,
        nextCode: String? = nil,
    ) -> VaultItemPreviewViewGeneratorMock {
        .mockGenerating { _, _, behaviour in
            let viewModel = OTPCodePreviewViewModel(
                accountName: "",
                issuer: "",
                color: .default,
                isLocked: false,
                fixedCodeState: .visible("123456"),
                fixedNextCode: nextCode,
            )
            if isHOTP {
                HOTPCodePreviewView(
                    buttonView: OTPCodeButtonIcon(isError: false),
                    previewViewModel: viewModel,
                    behaviour: behaviour,
                )
            } else {
                TOTPCodePreviewView(
                    previewViewModel: viewModel,
                    timerView: HorizontalTimerProgressBarView(fractionCompleted: 0.6, color: .blue),
                    behaviour: behaviour,
                )
            }
        }
    }

    private func makePasteboard() -> Pasteboard {
        Pasteboard(SystemPasteboardMock(), localSettings: LocalSettings(defaults: .init(userDefaults: .standard)))
    }

    private func fixedTestDate() -> Date {
        Date(timeIntervalSince1970: 40000)
    }
}
