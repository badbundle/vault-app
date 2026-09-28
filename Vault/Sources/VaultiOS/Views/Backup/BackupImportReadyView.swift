import Foundation
import SwiftUI
import VaultFeed

/// The import sheet's last step, once the backup is decrypted: what importing will do to the vault, and the button
/// that does it. Once the backup is in, it says so instead.
@MainActor
struct BackupImportReadyView: View {
    var viewModel: BackupImportFlowViewModel
    var payload: VaultApplicationPayload
    /// Closes the whole import sheet.
    var close: () -> Void

    @State private var isImporting = false

    var body: some View {
        Form {
            if viewModel.importState == .success {
                importedSection
            } else {
                BackupImportHeaderSection(
                    title: context.readyToImportTitle,
                    subtitle: context.readyToImportDescription,
                    systemImage: context.systemImage,
                    color: context.color,
                    // Cleared while trying again, so the header goes back to what importing will do.
                    error: isImporting ? nil : importError,
                )
                importSection
            }
        }
        .animation(.snappy, value: viewModel.importState)
        .animation(.snappy, value: isImporting)
        .sensoryFeedback(.success, trigger: viewModel.importState) { _, newValue in
            newValue == .success
        }
        .navigationBarBackButtonHidden(isImporting || viewModel.importState.isFinished)
        .toolbar {
            if viewModel.importState.isFinished {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        close()
                    } label: {
                        Text("Done")
                    }
                }
            }
        }
    }

    private var context: BackupImportContext {
        viewModel.importContext
    }

    private var importError: PresentationError? {
        switch viewModel.importState {
        case let .error(error): error
        case .notStarted, .success: nil
        }
    }

    // MARK: - Import Section

    /// Named for what it does to the vault. Replacing the vault is destructive, as on the Restore page's row.
    private var importSection: some View {
        Section {
            ProminentActionButton(
                context.importActionTitle,
                systemImage: context.systemImage,
                role: context == .override ? .destructive : nil,
            ) {
                isImporting = true
                defer { isImporting = false }
                await viewModel.importPayload(payload: payload)
            }
        } footer: {
            if isImporting {
                HStack(alignment: .center, spacing: 6) {
                    ProgressView()
                    Text(context.importingMessage)
                }
            }
        }
    }

    // MARK: - Imported Section

    private var importedSection: some View {
        Section {
            BackupHeroHeader(
                title: context.importedTitle,
                subtitle: context.importedDescription,
                systemImage: "checkmark.circle.fill",
                color: .green,
                bouncesOnAppear: true,
            )
        }
    }
}
