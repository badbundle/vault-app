import Foundation
import SwiftUI
import VaultSettings

/// The New Items section of Settings: what a new code or note starts with.
///
/// These only set where a new item's editor starts, so each item can still be changed on its own, and changing them
/// never touches an existing item (MANIFESTO C1). There's deliberately nothing here for hiding items, search
/// passphrases or killphrases, which are set up item by item (C1, C9).
struct NewItemsSettingsSection: View {
    @Bindable var localSettings: LocalSettings

    var body: some View {
        Section {
            Toggle(isOn: $localSettings.state.lockNewItems) {
                FormRow(image: Image(systemName: "lock.doc.fill"), color: SettingsIconColor.newItems) {
                    Text("Lock New Items")
                }
            }
            Toggle(isOn: $localSettings.state.showNewCodesInQuickType) {
                FormRow(image: Image(systemName: "keyboard.fill"), color: SettingsIconColor.newItems) {
                    Text("Show New Codes in QuickType")
                }
            }
        } header: {
            Text("New Items")
        } footer: {
            Text(
                "What new codes and notes start with. You can still change each item, and existing items aren't affected. Recovery phrases are always locked.",
            )
        }
    }
}
