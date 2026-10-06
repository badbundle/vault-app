import AppKit
import SwiftUI

/// What the Mac app adds to, and takes out of, the standard menus.
struct VaultMacCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @State private var appLock = VaultMacRoot.appLockService
    @FocusedValue(\.vaultMacFindAction) private var find
    @FocusedValue(\.vaultMacCopyCodeAction) private var copyCode

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
        // Copy copies the open item's code when no text has focus, through Vault's clipboard (G50). The rest go to
        // whatever has focus, as AppKit's own commands do.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { send(#selector(NSText.cut(_:))) }
                .keyboardShortcut("x")
            Button("Copy") {
                if let copyCode, !isEditingText {
                    copyCode()
                } else {
                    send(#selector(NSText.copy(_:)))
                }
            }
            .keyboardShortcut("c")
            Button("Paste") { send(#selector(NSText.paste(_:))) }
                .keyboardShortcut("v")
            Button("Select All") { send(#selector(NSText.selectAll(_:))) }
                .keyboardShortcut("a")
        }
        // Find is the main window's search. Spelling, Substitutions and the other text menus are left out: nothing
        // typed into Vault is checked or changed (G52).
        CommandGroup(replacing: .textEditing) {
            Button("Find") {
                find?()
            }
            .keyboardShortcut("f")
            .disabled(find == nil)
        }
    }
}

extension VaultMacCommands {
    /// Whether text has focus, such as the search field, so Copy copies what's selected in it.
    @MainActor
    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    @MainActor
    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
