import Foundation
import SwiftUI
import VaultFeed
import VaultKeygen

@MainActor
struct BackupRestoreView: View {
    @Environment(VaultDataModel.self) var dataModel
    @Environment(VaultInjector.self) var injector
    @State private var viewModel = BackupRestoreViewModel()
    @State private var modal: Modal?

    enum Modal: IdentifiableSelf {
        case importToCurrentlyEmpty(DerivedEncryptionKey?)
        case importAndMerge(DerivedEncryptionKey?)
        case importAndOverride(DerivedEncryptionKey?)
    }

    var body: some View {
        Form {
            if dataModel.hasAnyItems {
                mergeImportSection
                overrideImportSection
            } else {
                emptyVaultImportSection
            }
        }
        .navigationTitle(Text(viewModel.strings.homeTitle))
        .task {
            await dataModel.reloadItems()
        }
        .sheet(item: $modal, onDismiss: nil) { sheet in
            switch sheet {
            case let .importToCurrentlyEmpty(backupPassword):
                BackupImportFlowView(viewModel: .init(
                    importContext: .toEmptyVault,
                    dataModel: dataModel,
                    existingBackupPassword: backupPassword,
                    encryptedVaultDecoder: injector.encryptedVaultDecoder,
                ))
            case let .importAndMerge(backupPassword):
                BackupImportFlowView(viewModel: .init(
                    importContext: .merge,
                    dataModel: dataModel,
                    existingBackupPassword: backupPassword,
                    encryptedVaultDecoder: injector.encryptedVaultDecoder,
                ))
            case let .importAndOverride(backupPassword):
                BackupImportFlowView(viewModel: .init(
                    importContext: .override,
                    dataModel: dataModel,
                    existingBackupPassword: backupPassword,
                    encryptedVaultDecoder: injector.encryptedVaultDecoder,
                ))
            }
        }
    }
}

// MARK: - BackupRestoreView Extensions

extension BackupRestoreView {
    private var emptyVaultImportSection: some View {
        Section {
            importButton(
                title: "Import Backup",
                icon: "square.and.arrow.down",
            ) {
                modal = .importToCurrentlyEmpty(dataModel.backupPassword.fetchedPassword)
            }
        } footer: {
            Text("Import data from a Vault backup using a PDF file or by scanning QR codes from another device.")
        }
    }

    private var mergeImportSection: some View {
        Section {
            importButton(
                title: "Import & Merge",
                icon: "square.and.arrow.down.on.square",
            ) {
                modal = .importAndMerge(dataModel.backupPassword.fetchedPassword)
            }
        } header: {
            Text("Recommended")
        } footer: {
            Text(
                "Import from a PDF file or scan QR codes from another device. Merges with existing data, keeping the most recent version of each item.",
            )
        }
    }

    private var overrideImportSection: some View {
        Section {
            importButton(
                title: "Import & Override",
                icon: "exclamationmark.triangle.fill",
                isDestructive: true,
            ) {
                modal = .importAndOverride(dataModel.backupPassword.fetchedPassword)
            }
        } footer: {
            Text(
                "Import from a PDF file or scan QR codes and replace all existing data. On-device data will be lost if it is not in the backup.",
            )
        }
    }

    /// A single import action row.
    ///
    /// Every import path needs the backup password loaded before the sheet can be presented, so that
    /// is done here rather than repeated at each call site.
    private func importButton(
        title: String,
        icon: String,
        isDestructive: Bool = false,
        presentModal: @escaping () -> Void,
    ) -> some View {
        ProminentActionButton(title, systemImage: icon, role: isDestructive ? .destructive : nil) {
            await dataModel.loadBackupPassword()
            presentModal()
        }
    }
}
