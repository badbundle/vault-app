import SwiftUI

/// The Mac app's scenes: its one main window, the About window and Settings (docs/mac-app.md).
///
/// None of them is restored at launch, so macOS never saves what a window showed.
@MainActor
public struct VaultMacScene: Scene {
    public init() {
        // Before anything reads a setting.
        VaultMacSettingsArguments.removeVaultSettings()
        VaultMacRoot.setup()
    }

    public var body: some Scene {
        Window(VaultMacWindow.main.title, id: VaultMacWindow.main.id) {
            VaultMacRootView()
        }
        .defaultSize(width: 960, height: 640)
        .restorationBehavior(.disabled)
        .commands {
            VaultMacCommands()
        }

        Window(VaultMacWindow.about.title, id: VaultMacWindow.about.id) {
            VaultMacAboutWindowContent()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        // Opened from the Vault menu, as an About window is, rather than listed in the Window menu.
        .commandsRemoved()

        Window(VaultMacWindow.help.title, id: VaultMacWindow.help.id) {
            VaultMacHelpView(model: VaultMacRoot.help)
        }
        .defaultSize(width: 860, height: 600)
        .restorationBehavior(.disabled)
        // Opened from the Help menu and the About window, rather than listed in the Window menu.
        .commandsRemoved()

        // Its tab view is its root, so it gets the Mac's settings window, with the tabs in the toolbar. Each tab locks
        // on its own.
        Settings {
            VaultMacSettingsView(
                localSettings: VaultMacRoot.localSettings,
                appLock: VaultMacRoot.appLockService,
                dataModel: VaultMacRoot.vaultDataModel,
                authentication: VaultMacRoot.deviceAuthenticationService,
            )
        }
        .restorationBehavior(.disabled)
    }
}

/// The Mac app's windows, other than Settings.
enum VaultMacWindow: CaseIterable {
    /// The vault: its sidebar, the list of items and the selected item.
    case main
    /// The app's name, version and links.
    case about
    /// The FAQ, policies and libraries.
    case help

    var id: String {
        switch self {
        case .main: "main"
        case .about: "about"
        case .help: "help"
        }
    }

    /// What the window's title says, and the Window menu lists: never anything from the vault.
    var title: String {
        switch self {
        case .main: "Vault"
        case .about: "About Vault"
        case .help: "Vault Help"
        }
    }
}

/// The About window, which opens the Help window at a page.
private struct VaultMacAboutWindowContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VaultMacAboutView { page in
            VaultMacRoot.help.selection = page
            openWindow(id: VaultMacWindow.help.id)
        }
    }
}
