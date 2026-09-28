import Foundation
import Testing
import VaultCore
@testable import VaultFeed

struct PresentationValueCoverageTests {
    @Test
    func vaultItemVisibility_exposesIconsAndLocalizedText() {
        for value in VaultItemVisibility.allCases {
            #expect(value.systemIconName.isEmpty == false)
            #expect(value.localizedTitle.isEmpty == false)
            #expect(value.localizedSubtitle.isEmpty == false)
        }
    }

    @Test
    func vaultItemSearchableLevel_exposesIconsAndLocalizedText() {
        for value in VaultItemSearchableLevel.allCases {
            #expect(value.systemIconName.isEmpty == false)
            #expect(value.localizedTitle.isEmpty == false)
            #expect(value.localizedSubtitle.isEmpty == false)
        }
    }

    @Test
    func vaultItemLockState_exposesLockToggleAndLocalizedText() {
        var unlocked = VaultItemLockState.notLocked
        var locked = VaultItemLockState.lockedWithNativeSecurity

        #expect(unlocked.isLocked == false)
        #expect(locked.isLocked)

        unlocked.isLocked = true
        locked.isLocked = false

        #expect(unlocked == .lockedWithNativeSecurity)
        #expect(locked == .notLocked)

        for value in VaultItemLockState.allCases {
            #expect(value.systemIconName.isEmpty == false)
            #expect(value.localizedTitle.isEmpty == false)
        }
    }

    @Test
    func vaultItemViewConfiguration_mapsVisibilityAndSearchableLevel() {
        let cases: [(VaultItemVisibility, VaultItemSearchableLevel, VaultItemViewConfiguration)] = [
            (.always, .none, .alwaysVisible),
            (.onlySearch, .none, .alwaysVisible),
            (.onlySearch, .full, .alwaysVisible),
            (.onlySearch, .onlyTitle, .alwaysVisible),
            (.onlySearch, .onlyPassphrase, .requiresSearchPassphrase),
        ]

        for (visibility, searchableLevel, expected) in cases {
            #expect(VaultItemViewConfiguration(visibility: visibility, searchableLevel: searchableLevel) == expected)
        }
    }

    @Test
    func vaultItemViewConfiguration_exposesDerivedValuesAndLocalizedText() {
        var configuration = VaultItemViewConfiguration.alwaysVisible
        #expect(configuration.visibility == .always)
        #expect(configuration.searchableLevel == .full)
        #expect(configuration.isEnabled == false)

        configuration.isEnabled = true
        #expect(configuration == .requiresSearchPassphrase)
        #expect(configuration.visibility == .onlySearch)
        #expect(configuration.searchableLevel == .onlyPassphrase)

        for value in VaultItemViewConfiguration.allCases {
            #expect(value.systemIconName.isEmpty == false)
            #expect(value.localizedTitle.isEmpty == false)
        }
    }

    @Test
    func notePreviewMode_exposesLocalizedTitles() {
        for value in NotePreviewMode.allCases {
            #expect(value.localizedTitle.isEmpty == false)
        }
    }

    @Test
    func otpCodeState_exposesGenerationAndVisibilityFlags() {
        let error = PresentationError(userTitle: "title", userDescription: "description", debugDescription: "debug")
        let cases: [(OTPCodeState, Bool, Bool)] = [
            (.notReady, false, false),
            (.finished, false, false),
            (.obfuscated(.privacy), true, false),
            (.obfuscated(.expiry), true, false),
            (.visible("123456"), true, true),
            (.locked(code: "123456"), true, false),
            (.error(error, digits: 6), false, false),
        ]

        for (state, allowsNextCode, isVisible) in cases {
            #expect(state.allowsNextCodeToBeGenerated == allowsNextCode)
            #expect(state.isVisible == isVisible)
        }
    }

    @Test
    func loadingAndValidationStates_exposeConvenienceFlags() {
        #expect(LoadingState.loading.isLoading)
        #expect(LoadingState.loading.isNotLoading == false)
        #expect(LoadingState.notLoading.isLoading == false)
        #expect(LoadingState.notLoading.isNotLoading)

        #expect(FieldValidationState.valid.isValid)
        #expect(FieldValidationState.valid.isError == false)
        #expect(FieldValidationState.invalid.isValid == false)
        #expect(FieldValidationState.invalid.message == nil)
        #expect(FieldValidationState.error(message: "Bad").isError)
        #expect(FieldValidationState.error(message: "Bad").message == "Bad")
    }

    @Test
    func textFormatAndSimplePresentationModels_exposeValues() {
        #expect(TextFormat.markdown.localizedString == "Markdown")
        #expect(TextFormat.plain.localizedString == "Plain")

        let entry = DetailEntry(title: "Title", detail: "Detail", systemIconName: "info")
        let item = DetailMenuItem(id: "id", title: "Menu", systemIconName: "list.bullet", entries: [entry])

        #expect(item.id == "id")
        #expect(item.entries.first?.detail == "Detail")
    }

    @Test
    func vaultBackupEventKind_localizesAndCodableRoundTrips() throws {
        let cases: [VaultBackupEvent.Kind] = [
            .exportedToPDF,
            .importedToPDF,
            .exportedToDevice,
            .importedFromDevice,
            .exportedToAutoBackup(providerID: "provider"),
        ]

        for value in cases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(VaultBackupEvent.Kind.self, from: data)

            #expect(value.localizedTitle.isEmpty == false)
            #expect(decoded == value)
        }
    }

    @Test
    func vaultItemColor_exposesDefaultsAndBrightening() {
        #expect(VaultItemColor.default == .gray)
        #expect(VaultItemColor.tagDefault.red == 0)
        #expect(VaultItemColor.black == .init(red: 0, green: 0, blue: 0))
        #expect(VaultItemColor.white == .init(red: 1, green: 1, blue: 1))

        let brightened = VaultItemColor(red: 0.2, green: 0.3, blue: 0.4).brighten(amount: 0.5)

        #expect(brightened.red > 0.2)
        #expect(brightened.green > 0.4)
        #expect(brightened.blue > 0.3)
    }

    @Test
    func backupImportContext_exposesReadyText() {
        let contexts: [BackupImportContext] = [.toEmptyVault, .merge, .override]

        for context in contexts {
            #expect(context.readyToImportTitle.isEmpty == false)
            #expect(context.readyToImportDescription.isEmpty == false)
            #expect(context.importActionTitle.isEmpty == false)
            #expect(context.importingMessage.isEmpty == false)
            #expect(context.importedTitle.isEmpty == false)
            #expect(context.importedDescription.isEmpty == false)
        }
    }

    @Test
    func backupPDFSizesExposeTitlesAndAspectRatios() {
        for size in BackupCreatePDFViewModel.Size.allCases {
            #expect(size.localizedTitle.isEmpty == false)
            #expect(size.aspectRatio > 0)
        }
    }

    @Test
    func autoBackupRetentionExposeTitlesAndCleanupBehavior() {
        let expectedCleanup: [AutoBackupRetention: Bool] = [
            .days7: true,
            .days30: true,
            .year1: true,
            .forever: false,
        ]

        for retention in AutoBackupRetention.allCases {
            #expect(retention.localizedTitle.isEmpty == false)
            #expect(retention.shouldCleanup == expectedCleanup[retention])
        }
    }

    @Test
    func encryptedItemPreviewVisibleTitleDependsOnPreviewModeAndTitle() {
        let color = VaultItemColor(red: 0.1, green: 0.2, blue: 0.3)

        #expect(EncryptedItemPreviewViewModel(title: "Secret", color: color, previewMode: .titleOnly)
            .visibleTitle == "Secret")
        #expect(EncryptedItemPreviewViewModel(title: "   ", color: color, previewMode: .titleAndFirstLine)
            .visibleTitle == "Untitled Item")
        #expect(EncryptedItemPreviewViewModel(title: "Secret", color: color, previewMode: .hidden).visibleTitle
            .isEmpty == false)
    }
}
