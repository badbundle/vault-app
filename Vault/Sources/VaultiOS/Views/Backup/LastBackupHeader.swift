import CryptoEngine
import Foundation
import SwiftUI
import VaultFeed

/// The Backups page's headline: when this device last backed up, or a warning if it never has.
///
/// The symbol is tinted by how long ago that was: green within a week, orange within 30 days and
/// red after that, or if there's no backup at all.
struct LastBackupHeader: View {
    var lastBackup: VaultBackupEvent?
    /// Injectable so snapshots can pin how stale the backup is.
    var now: Date = .init()

    var body: some View {
        BackupHeroHeader(
            title: "Backups",
            subtitle: subtitle,
            systemImage: systemImage,
            color: color,
            iconSize: 56,
        )
    }

    private var subtitle: String {
        guard let lastBackup else {
            return "You haven't made a backup on this device yet. Without one, you could lose your vault."
        }
        // On two lines rather than joined with a separator, which would be left dangling at the end
        // of the first line whenever the two don't fit on one.
        let date = lastBackup.backupDate.formatted(date: .abbreviated, time: .shortened)
        return "Last backup \(date)\n\(lastBackup.kind.localizedTitle)"
    }

    private var systemImage: String {
        lastBackup == nil ? "externaldrive.fill.badge.exclamationmark" : "externaldrive.fill.badge.timemachine"
    }

    private var color: Color {
        switch lastBackup?.staleness(at: now) {
        case .recent: .green
        case .stale: .orange
        case .veryStale, nil: .red
        }
    }
}

#Preview {
    let now = Date()
    func backup(daysAgo: Double) -> VaultBackupEvent {
        let date = now.addingTimeInterval(-daysAgo * 24 * 60 * 60)
        return VaultBackupEvent(
            backupDate: date,
            eventDate: date,
            kind: .exportedToPDF,
            payloadHash: .init(value: Data(hex: "ababa")),
        )
    }

    return Form {
        Section { LastBackupHeader(lastBackup: nil, now: now) }
        Section { LastBackupHeader(lastBackup: backup(daysAgo: 1), now: now) }
        Section { LastBackupHeader(lastBackup: backup(daysAgo: 10), now: now) }
        Section { LastBackupHeader(lastBackup: backup(daysAgo: 100), now: now) }
    }
}
