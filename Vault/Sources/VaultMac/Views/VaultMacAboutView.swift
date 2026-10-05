import SwiftUI
import VaultAppIcon

/// The About window: the app's icon, name and version.
struct VaultMacAboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            VaultAppIconView()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("Vault")
                .font(.title.bold())
            Text(Self.version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("about.version")
        }
        .padding(32)
        .frame(width: 320)
    }

    /// "Version 2.0 (100016)", from the app's Info.plist.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}
