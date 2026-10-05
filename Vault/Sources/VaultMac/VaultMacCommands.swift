import SwiftUI

/// What the Mac app adds to, and takes out of, the standard menus.
struct VaultMacCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Vault") {
                openWindow(id: VaultMacWindow.about.id)
            }
        }
        // There's only ever one main window, and ⌘N will be New Item.
        CommandGroup(replacing: .newItem) {}
    }
}
