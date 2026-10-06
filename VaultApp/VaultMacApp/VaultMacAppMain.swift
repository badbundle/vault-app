import SwiftUI
import VaultMac

@main
@MainActor
struct VaultMacApp: App {
    @NSApplicationDelegateAdaptor(VaultMacAppDelegate.self) private var appDelegate

    var body: some Scene {
        VaultMacScene()
    }
}
