import SwiftUI
import VaultFeed

/// The Backups area's middle column: when this Mac last backed up, then each page.
struct VaultMacBackupsList: View {
    @Binding var selection: VaultMacBackupsPage?
    var services: VaultMacBackupServices
    /// Injectable so snapshots can pin how long ago the last backup was.
    var now: Date = .init()

    /// The latest value from the service's configuration publisher, which doesn't replay.
    @State private var publishedAutoBackupEnabled: Bool?
    /// Likewise its status, which says when a backup couldn't be made.
    @State private var publishedAutoBackupStatus: AutoBackupStatus?

    var body: some View {
        List(selection: $selection) {
            Section {
                header
            }
            Section {
                ForEach(VaultMacBackupsPage.allCases) { page in
                    VaultMacBackupsRow(page: page, status: status(of: page))
                        // Of the selection's own type, so the list shows the open page as selected.
                        .tag(VaultMacBackupsPage?.some(page))
                        .accessibilityIdentifier("backups.\(page.rawValue)")
                }
            }
        }
        .task {
            await services.dataModel.loadBackupPasswordStatus()
        }
        .onReceive(services.autoBackupService.configurationPublisher) { configuration in
            publishedAutoBackupEnabled = configuration.isEnabled
        }
        .onReceive(services.autoBackupService.statusPublisher) { status in
            publishedAutoBackupStatus = status
        }
        .accessibilityIdentifier("backups")
    }

    private func status(of page: VaultMacBackupsPage) -> String? {
        switch page {
        case .autoBackup:
            if !(publishedAutoBackupEnabled ?? services.autoBackupService.configuration.isEnabled) {
                "Off"
            } else if case .error = publishedAutoBackupStatus ?? services.autoBackupService.status {
                "Needs Attention"
            } else {
                "On"
            }
        case .password:
            switch services.dataModel.backupPasswordStatus {
            case .unknown: nil
            case .notSet: "Not Set"
            case .set: "Set"
            }
        case .keepABackup, .transfer, .restore:
            nil
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: lastBackup == nil
                ? "externaldrive.fill.badge.exclamationmark"
                : "externaldrive.fill.badge.timemachine")
                .font(.system(size: 28))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Backups")
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("backups.last-backup")
    }

    private var lastBackup: VaultBackupEvent? {
        services.dataModel.lastBackupEvent
    }

    private var subtitle: String {
        guard let lastBackup else {
            return "You haven't made a backup on this Mac yet. Without one, you could lose your vault."
        }
        let date = lastBackup.backupDate.formatted(date: .abbreviated, time: .shortened)
        return "Last backup \(date)\n\(lastBackup.kind.localizedTitle)"
    }

    /// Green within a week, orange within 30 days, and red after that or with no backup, as on iOS.
    private var color: Color {
        switch lastBackup?.staleness(at: now) {
        case .recent: .green
        case .stale: .orange
        case .veryStale, nil: .red
        }
    }
}

/// Shows its content only once the backup password is loaded, which asks for Touch ID or the Mac's password first,
/// as on iOS. Until then it offers to authenticate, or to set the password up if there isn't one.
struct VaultMacBackupKeyGate<Content: View>: View {
    var services: VaultMacBackupServices
    /// Why the page needs the password, shown before it's loaded.
    var purpose: String
    var setUpPassword: () -> Void
    @ViewBuilder var content: (DerivedEncryptionKey) -> Content

    var body: some View {
        switch services.dataModel.backupPassword {
        case let .fetched(key):
            content(key)
        case .notCreated:
            VaultMacBackupNotice(
                systemImage: "lock.shield",
                title: "Set Up a Backup Password",
                message: "Backups are encrypted with your backup password, so you'll need to set one up first.",
                action: ("Set Up Backup Password…", setUpPassword),
            )
        case .notFetched:
            VaultMacBackupNotice(
                systemImage: "key.horizontal",
                title: "Authenticate",
                message: purpose,
                action: ("Authenticate", { Task { await services.dataModel.loadBackupPassword() } }),
            )
        case let .error(error):
            VaultMacBackupNotice(
                systemImage: "exclamationmark.triangle",
                title: error.userTitle,
                message: error.userDescription ?? purpose,
                action: ("Try Again", { Task { await services.dataModel.loadBackupPassword() } }),
            )
        }
    }
}

/// A page's message, when there's something to do before it can show more.
struct VaultMacBackupNotice: View {
    var systemImage: String
    var title: String
    var message: String
    var action: (title: String, perform: () -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let action {
                Button(action.title, action: action.perform)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("backups.notice-action")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One of the Backups pages in the list: its symbol, its name and how it stands, spaced as the Items list's rows are.
struct VaultMacBackupsRow: View {
    var page: VaultMacBackupsPage
    var status: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: page.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(page.title)
                .font(.body.weight(.medium))
            Spacer(minLength: 8)
            if let status {
                Text(status)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
