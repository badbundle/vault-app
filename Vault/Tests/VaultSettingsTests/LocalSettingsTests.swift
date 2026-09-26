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
    func universalClipboard_savesStateAfterStateChanged() throws {
        let defaults = try Defaults.nonPersistent()
        let sutSave = try makeSUT(defaults: defaults)
        sutSave.state.allowUniversalClipboardForOTPs = true

        let sutRetrieve = try makeSUT(defaults: defaults)
        #expect(sutRetrieve.state.allowUniversalClipboardForOTPs)
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
