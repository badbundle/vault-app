import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultSettings

@MainActor
struct LocalSettingsTests {
    @Test
    func pasteTimeToLive_defaultsToDefaultValue() throws {
        let defaults = try Defaults.nonPersistent()
        let sut = try makeSUT(defaults: defaults)

        #expect(sut.state.pasteTimeToLive == .default)
    }

    @Test
    func pasteTimeToLive_defaultsToOneMinute() throws {
        let sut = try makeSUT(defaults: .nonPersistent())

        #expect(sut.state.pasteTimeToLive == .init(duration: 60))
    }

    @Test
    func pasteTimeToLive_readingTheDefaultDoesNotStoreIt() throws {
        let defaults = try Defaults.nonPersistent()
        let sut = try makeSUT(defaults: defaults)

        _ = sut.state.pasteTimeToLive

        // Only a choice is stored, so a later change to the default reaches everyone who never chose.
        #expect(!defaults.has(Key<PasteTTL>(VaultIdentifiers.Preferences.General.settingsPasteTTL)))
    }

    @Test
    func pasteTimeToLive_keepsAnExplicitChoiceOfNoExpiry() throws {
        let defaults = try Defaults.nonPersistent()
        let sutSave = try makeSUT(defaults: defaults)
        sutSave.state.pasteTimeToLive = .init(duration: nil)

        let sutRetrieve = try makeSUT(defaults: defaults)
        #expect(sutRetrieve.state.pasteTimeToLive == .init(duration: nil))
    }

    @Test
    func pasteTimeToLive_keepsNoExpiryChosenInEarlierVersions() throws {
        let suiteName = UUID().uuidString
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        // What choosing "No expiry" has always stored: the JSON of a `PasteTTL` without a duration.
        userDefaults.set(Data("{}".utf8), forKey: VaultIdentifiers.Preferences.General.settingsPasteTTL)

        let sut = try makeSUT(defaults: Defaults(userDefaults: userDefaults))

        #expect(sut.state.pasteTimeToLive == .init(duration: nil))
    }

    @Test
    func pasteTimeToLive_savesStateAfterStateChanged() throws {
        let defaults = try Defaults.nonPersistent()
        let sutSave = try makeSUT(defaults: defaults)
        sutSave.state.pasteTimeToLive = .init(duration: 1234)

        let sutRetrieve = try makeSUT(defaults: defaults)
        #expect(sutRetrieve.state.pasteTimeToLive == .init(duration: 1234))
    }

    @Test
    func universalClipboard_isOffForEveryContentTypeByDefault() throws {
        let sut = try makeSUT(defaults: .nonPersistent())

        for contentType in PasteboardContentType.allCases {
            #expect(!sut.state.isUniversalClipboardAllowed(for: contentType))
        }
        #expect(!sut.state.isUniversalClipboardAllowedForAny)
    }

    @Test
    func universalClipboard_allowsOTPsOnceTurnedOn() throws {
        let sut = try makeSUT(defaults: .nonPersistent())

        sut.state.allowUniversalClipboardForOTPs = true

        #expect(sut.state.isUniversalClipboardAllowed(for: .otp))
        #expect(sut.state.isUniversalClipboardAllowedForAny)
    }

    @Test
    func hidesVaultWhileScreenCaptured_isOnByDefault() throws {
        let sut = try makeSUT(defaults: .nonPersistent())

        #expect(sut.state.hidesVaultWhileScreenCaptured)
    }

    @Test
    func hidesVaultWhileScreenCaptured_savesStateAfterTurningOffAndOn() throws {
        let defaults = try Defaults.nonPersistent()
        let sut = try makeSUT(defaults: defaults)

        sut.state.hidesVaultWhileScreenCaptured = false
        #expect(try !makeSUT(defaults: defaults).state.hidesVaultWhileScreenCaptured)

        sut.state.hidesVaultWhileScreenCaptured = true
        #expect(try makeSUT(defaults: defaults).state.hidesVaultWhileScreenCaptured)
    }

    @Test
    func codeTapAction_copiesByDefault() throws {
        let sut = try makeSUT(defaults: .nonPersistent())

        #expect(sut.state.codeTapAction == .copy)
    }

    @Test(arguments: CodeTapAction.allCases)
    func codeTapAction_savesStateAfterStateChanged(codeTapAction: CodeTapAction) throws {
        let defaults = try Defaults.nonPersistent()
        let sutSave = try makeSUT(defaults: defaults)
        sutSave.state.codeTapAction = codeTapAction

        let sutRetrieve = try makeSUT(defaults: defaults)
        #expect(sutRetrieve.state.codeTapAction == codeTapAction)
    }

    @Test
    func universalClipboard_savesStateAfterStateChanged() throws {
        let defaults = try Defaults.nonPersistent()
        let sutSave = try makeSUT(defaults: defaults)
        sutSave.state.allowUniversalClipboardForOTPs = true

        let sutRetrieve = try makeSUT(defaults: defaults)
        #expect(sutRetrieve.state.allowUniversalClipboardForOTPs)
    }

    @Test
    func newItems_startUnlockedAndOutOfQuickTypeByDefault() throws {
        let sut = try makeSUT(defaults: .nonPersistent())

        #expect(sut.state.lockNewItems == false)
        #expect(sut.state.showNewCodesInQuickType == false)
    }

    @Test
    func newItems_savesStateAfterStateChanged() throws {
        let defaults = try Defaults.nonPersistent()
        let sutSave = try makeSUT(defaults: defaults)
        sutSave.state.lockNewItems = true
        sutSave.state.showNewCodesInQuickType = true

        let sutRetrieve = try makeSUT(defaults: defaults)
        #expect(sutRetrieve.state.lockNewItems)
        #expect(sutRetrieve.state.showNewCodesInQuickType)
    }
}

// MARK: - Helpers

extension LocalSettingsTests {
    private func makeSUT(defaults: Defaults) throws -> LocalSettings {
        LocalSettings(defaults: defaults)
    }
}

extension UserDefaults {
    private var allStoredKeys: [String] {
        dictionaryRepresentation().keys.map(\.self)
    }
}
