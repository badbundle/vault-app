import BadBundleApps
import SwiftUI
import VaultAppIcon

/// The About window: the app's icon, name and version, its policies and libraries, where its source is, and the
/// other Bad Bundle apps.
struct VaultMacAboutView: View {
    /// "Version 2.0 (100016)": the app's, though snapshot tests give a fixed one.
    var version = Self.version
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
                Text(version)
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
            links
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

    /// The policies, libraries and open source, each opening its Help page: on one line if they all fit, otherwise two
    /// to a line, otherwise one to a line, so no title is ever cut off.
    private var links: some View {
        ViewThatFits(in: .horizontal) {
            linkLines(perLine: VaultMacHelpPage.about.count)
            linkLines(perLine: 2)
            linkLines(perLine: 1)
        }
        .font(.callout)
    }

    private func linkLines(perLine: Int) -> some View {
        let pages = VaultMacHelpPage.about
        let lines = stride(from: 0, to: pages.count, by: perLine).map {
            Array(pages[$0 ..< min($0 + perLine, pages.count)])
        }
        return VStack(spacing: 6) {
            ForEach(lines, id: \.self) { line in
                HStack(spacing: 8) {
                    ForEach(line) { page in
                        if page != line.first {
                            Text("·")
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        Button(page.title) { openHelp(page) }
                            .buttonStyle(.link)
                            .fixedSize()
                            .accessibilityIdentifier("about.link.\(page.rawValue)")
                    }
                }
            }
        }
    }

    /// "Version 2.0 (100016)", from the app's Info.plist.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}
