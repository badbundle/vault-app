import Foundation
import SwiftUI
import VaultBackup

/// A backup's seal, small, with its code: under a header, to say which backup a screen is about.
///
/// The code matches the one printed beside the seal on the backup's PDF, and in each of its pages' headers.
struct BackupSealLabel: View {
    var seal: BackupSeal

    @ScaledMetric(relativeTo: .footnote) private var sealSize: Double = 22

    var body: some View {
        // Not a `Label`: inside a form row, its icon takes the row's icon column width.
        HStack(spacing: 8) {
            BackupSealView(seal: seal)
                .frame(width: sealSize)
            Text(verbatim: "Seal \(seal.code)")
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Backup Seal"))
        .accessibilityValue(Text(seal.spokenCode))
    }
}
