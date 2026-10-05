import SwiftUI

/// What the Mac app adds to, and takes out of, the standard menus.
struct VaultMacCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @State private var appLock = VaultMacRoot.appLockService

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Vault") {
                openWindow(id: VaultMacWindow.about.id)
            }
        }
        CommandGroup(after: .appSettings) {
            Button("Lock Vault") {
                appLock.lockNow()
            }
            .keyboardShortcut("l", modifiers: [.control, .command])
            .disabled(appLock.isLocked || !appLock.isPasswordSet)
        }
        // There's only ever one main window, and ⌘N will be New Item.
        CommandGroup(replacing: .newItem) {}
    }
}
