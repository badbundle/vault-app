import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultBackup
@testable import VaultiOS

@MainActor
struct BackupSealViewSnapshotTests {
    /// Eight backups' seals and the label with a seal's code. Each seal's color, edge and rosettes come from its
    /// backup, so these are the same every run.
    @Test(arguments: [ColorScheme.light, .dark])
    func seals(colorScheme: ColorScheme) {
        let seals = (0 ..< 8).map { index in
            var vault = fixedEncryptedVault()
            vault.data[0] = UInt8(index)
            return BackupSeal(encryptedVault: vault)
        }
        let sut = VStack(spacing: 20) {
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                ForEach(0 ..< 2, id: \.self) { row in
                    GridRow {
                        ForEach(0 ..< 4, id: \.self) { column in
                            BackupSealView(seal: seals[row * 4 + column])
                                .frame(width: 80)
                        }
                    }
                }
            }
            BackupSealLabel(seal: seals[0])
        }
        .padding(20)
        .background(Color(uiColor: .systemGroupedBackground))
        .framedForTest(height: 300)

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }
}
