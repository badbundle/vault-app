import Foundation
import SwiftUI
import VaultFeed
import VaultSettings

extension EnvironmentValues {
    /// What a new item starts with, as chosen in Settings.
    ///
    /// Read when a new item's editor opens, so the item starts from the latest choice. Off unless set.
    @Entry var newItemDefaults = NewItemDefaults()
}

extension LocalSettingsState {
    /// What a new item starts with.
    var newItemDefaults: NewItemDefaults {
        NewItemDefaults(lockNewItems: lockNewItems, showNewCodesInQuickType: showNewCodesInQuickType)
    }
}
