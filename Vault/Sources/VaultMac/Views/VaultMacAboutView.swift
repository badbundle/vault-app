import BadBundleApps
import SwiftUI
import VaultAppIcon

/// The About window: the app's icon, name and version, its policies and libraries, where its source is, and the
/// other Bad Bundle apps.
struct VaultMacAboutView: View {
    var openHelp: (VaultMacHelpPage) -> Void

    var body: some View {
        VStack(spacing: 16) {
            VaultAppIconView()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Vault")
                    .font(.title.bold())
                Text(Self.version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("about.version")
            }
            Text(
                "Vault keeps the data you can't afford to lose or leak: two-factor codes, notes and recovery phrases, encrypted on this Mac and never online.",
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 320)
            HStack {
                ForEach(VaultMacHelpPage.about) { page in
                    Button(page.title) { openHelp(page) }
                        .buttonStyle(.link)
                }
            }
            .font(.callout)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("More Apps")
                    .font(.headline)
                ForEach(BadBundleApp.all(except: .vault)) { app in
                    BadBundleAppLink(app)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                Text("Copyright 2026 Bad Bundle Limited")
                Text("Made in the UK")
                Text("Open source")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 400)
    }

    /// "Version 2.0 (100016)", from the app's Info.plist.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}
