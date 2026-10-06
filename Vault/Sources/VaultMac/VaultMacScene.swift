import SwiftUI

/// The Mac app's scenes: its one main window, the About window and Settings (docs/mac-app.md).
///
/// None of them is restored at launch, so macOS never saves what a window showed.
@MainActor
public struct VaultMacScene: Scene {
    public init() {
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
            VaultMacAboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        // Opened from the Vault menu, as an About window is, rather than listed in the Window menu.
        .commandsRemoved()

        Settings {
            VaultMacLockedWindowGate {
                VaultMacSettingsView()
            }
            .frame(width: 480, height: 320)
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

    var id: String {
        switch self {
        case .main: "main"
        case .about: "about"
        }
    }

    /// What the window's title says, and the Window menu lists: never anything from the vault.
    var title: String {
        switch self {
        case .main: "Vault"
        case .about: "About Vault"
        }
    }
}
