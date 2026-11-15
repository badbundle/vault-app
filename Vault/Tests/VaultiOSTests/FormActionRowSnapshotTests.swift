import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultSettings
@testable import VaultiOS

@MainActor
struct FormActionRowSnapshotTests {
    /// Every kind of row a form offers an action with, so they stay one design: rows that act here, rows that open
    /// something, a row that leaves Vault, and each of them destructive, disabled or busy.
    @Test(arguments: [ColorScheme.light, .dark])
    func kinds(colorScheme: ColorScheme) {
        let sut = Form {
            Section {
                FormActionRow("Authenticate", systemImage: "key.horizontal.fill") {}
                FormActionRow("Back Up Now", systemImage: "arrow.clockwise.icloud", isLoading: true) {}
                FormActionRow("Decrypt", systemImage: "lock.open.fill") {}
                    .disabled(true)
                FormActionRow("Delete", systemImage: "trash.fill", role: .destructive) {}
                FormActionRow("Remove Encryption", systemImage: "lock.slash.fill", role: .destructive) {}
                    .disabled(true)
            } header: {
                Text("Acts here")
            }

            Section {
                FormActionRow("Choose Folder", systemImage: "folder.fill", kind: .disclosure) {}
                FormActionRow(
                    "PDF Backup",
                    subtitle: "An encrypted file you can save or print.",
                    systemImage: "doc.text.fill",
                    kind: .disclosure,
                ) {}
                FormActionRow(
                    "Save To",
                    value: "Vault Backups",
                    systemImage: "icloud",
                    color: .blue,
                    kind: .disclosure,
                ) {}
                FormActionRow(
                    "Import & Override",
                    systemImage: "exclamationmark.triangle.fill",
                    kind: .disclosure,
                    role: .destructive,
                ) {}
            } header: {
                Text("Opens something")
            }

            Section {
                Link(destination: VaultAppStore.writeReviewURL) {
                    FormActionRowLabel("Rate Vault", systemImage: "star.fill", color: .orange, kind: .external)
                }
            } header: {
                Text("Leaves Vault")
            }
        }
        .framedForTest()

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    /// At the largest text size the title and subtitle wrap beside the tile, and the chevron stays on the trailing
    /// edge.
    @Test
    func largestTextSize() {
        let sut = Form {
            FormActionRow(
                "Transfer with QR Codes",
                subtitle: "Show codes for another device to scan, without saving a file.",
                systemImage: "qrcode",
                color: .indigo,
                kind: .disclosure,
            ) {}
            FormActionRow("Set Backup Password", systemImage: "checkmark.shield.fill") {}
        }
        .dynamicTypeSize(.accessibility5)
        .framedForTest()

        assertSnapshot(of: sut, colorScheme: .light, named: "accessibility5")
    }
}
