import SwiftUI
import VaultBackup

/// A backup's seal with its code and a line about it, as a form row: on the Mac's Keep a Backup page once the PDF is
/// made, and above a backup's password when restoring or checking it.
struct VaultMacBackupSealRow: View {
    var seal: BackupSeal
    var caption: String

    var body: some View {
        HStack(spacing: 12) {
            BackupSealView(seal: seal)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Seal \(seal.code)")
                    .font(.body.monospaced().weight(.semibold))
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Backup Seal"))
        .accessibilityValue(Text(seal.spokenCode))
        .accessibilityHint(Text(caption))
    }
}
