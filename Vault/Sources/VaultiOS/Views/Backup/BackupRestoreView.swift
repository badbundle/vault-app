import Foundation
import SwiftUI
import VaultFeed

/// Screen for restoring from a backup: a PDF, or QR codes from another device.
///
/// Locked behind device authentication until the user passes it, and locked again when they leave
/// the page or the app goes to the background. Presenting the import sheet doesn't count as
/// leaving, so the page stays unlocked underneath it.
@MainActor
struct BackupRestoreView: View {
    @Environment(VaultDataModel.self) var dataModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: BackupRestoreViewModel
    @State private var modal: Modal?

    enum Modal: IdentifiableSelf {
        case importToCurrentlyEmpty
        case importAndMerge
        case importAndOverride
    }

    init(viewModel: BackupRestoreViewModel) {
        _viewModel = .init(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            headerSection

            switch viewModel.permissionState {
            case .undetermined:
                authenticateSection(isError: false)
            case .denied:
                authenticateSection(isError: true)
            case .unavailable:
                PasscodeRequiredSection(message: "Set up a passcode on this device to restore a backup.")
            case .allowed:
                // Only what the feed shows: a vault holding only items a search shows gets the same sections as an
                // empty one. Importing into it merges, so they're kept.
                if dataModel.hasVisibleItems {
                    mergeImportSection
                    overrideImportSection
                } else {
                    emptyVaultImportSection
                }
            }
        }
        .navigationTitle(Text(viewModel.strings.homeTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await dataModel.reloadHasVisibleItems()
        }
        .onDisappear {
            viewModel.lock()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background {
                viewModel.lock()
            }
        }
        // An import reloads the items for whatever search is set, so read again what the feed shows without one.
        .sheet(item: $modal, onDismiss: reloadHasVisibleItems) { sheet in
            switch sheet {
            case .importToCurrentlyEmpty:
                BackupImportFlowView(viewModel: .init(importContext: .toEmptyVault, dataModel: dataModel))
            case .importAndMerge:
                BackupImportFlowView(viewModel: .init(importContext: .merge, dataModel: dataModel))
            case .importAndOverride:
                BackupImportFlowView(viewModel: .init(importContext: .override, dataModel: dataModel))
            }
        }
    }
}

// MARK: - BackupRestoreView Extensions

extension BackupRestoreView {
    private func reloadHasVisibleItems() {
        Task { await dataModel.reloadHasVisibleItems() }
    }

    /// What restoring does, and what it needs, before anything else.
    private var headerSection: some View {
        Section {
            BackupHeroHeader(
                title: "Restore Your Vault",
                subtitle: "Import from a PDF backup or another device. You'll need the password the backup was made with.",
                systemImage: "square.and.arrow.down.fill",
                color: .accentColor,
                iconSize: 56,
            )
        }
    }

    private func authenticateSection(isError: Bool) -> some View {
        Section {
            FormActionRow("Authenticate", systemImage: "key.horizontal.fill") {
                await viewModel.authenticate()
            }
        } header: {
            Text(isError ? "Authentication Failed" : "Locked")
        } footer: {
            Text(
                isError
                    ? "Unable to verify your identity. Please try again."
                    : "Authenticate to restore a backup.",
            )
            .foregroundStyle(isError ? Color.red : Color.secondary)
        }
    }

    private var emptyVaultImportSection: some View {
        Section {
            importRow(title: "Import Backup", context: .toEmptyVault) {
                modal = .importToCurrentlyEmpty
            }
        } footer: {
            Text("Import data from a Vault backup using a PDF file or by scanning QR codes from another device.")
        }
    }

    private var mergeImportSection: some View {
        Section {
            importRow(title: "Import & Merge", context: .merge) {
                modal = .importAndMerge
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
            importRow(title: "Import & Override", context: .override) {
                modal = .importAndOverride
            }
        } footer: {
            Text(
                "Import from a PDF file or scan QR codes and replace all existing data. On-device data will be lost if it is not in the backup.",
            )
        }
    }

    /// A single import action row, with the symbol and color of the import sheet it opens. Replacing the vault is
    /// destructive.
    ///
    /// The import asks for the backup's own password, whatever backup password this device has, so nothing is loaded
    /// first.
    private func importRow(
        title: String,
        context: BackupImportContext,
        presentModal: @escaping () -> Void,
    ) -> some View {
        FormActionRow(
            title,
            systemImage: context.systemImage,
            color: context.color,
            kind: .disclosure,
            role: context == .override ? .destructive : nil,
            actionOptions: [],
        ) {
            presentModal()
        }
    }
}
