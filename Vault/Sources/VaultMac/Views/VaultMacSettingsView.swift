import SwiftUI

/// The Settings window (⌘,).
struct VaultMacSettingsView: View {
    var body: some View {
        ContentUnavailableView("Settings", systemImage: "gear")
            .frame(width: 480, height: 320)
    }
}
