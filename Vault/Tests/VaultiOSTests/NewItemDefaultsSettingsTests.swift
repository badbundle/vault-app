import Foundation
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
struct NewItemDefaultsSettingsTests {
    @Test
    func newItemDefaults_areOffWhenNothingIsChosen() throws {
        let settings = try LocalSettings(defaults: .nonPersistent())

        #expect(settings.state.newItemDefaults == NewItemDefaults())
    }

    @Test(arguments: [false, true], [false, true])
    func newItemDefaults_followTheSettings(lockNewItems: Bool, showNewCodesInQuickType: Bool) throws {
        let settings = try LocalSettings(defaults: .nonPersistent())
        settings.state.lockNewItems = lockNewItems
        settings.state.showNewCodesInQuickType = showNewCodesInQuickType

        #expect(settings.state.newItemDefaults == NewItemDefaults(
            lockNewItems: lockNewItems,
            showNewCodesInQuickType: showNewCodesInQuickType,
        ))
    }
}
