import Foundation
import SwiftUI
import UniformTypeIdentifiers
import VaultFeed

/// Screen for configuring and monitoring auto-backup.
@MainActor
struct AutoBackupView: View {
    @Environment(VaultDataModel.self) var dataModel
    @Environment(DeviceAuthenticationService.self) var authenticationService
    @Environment(VaultInjector.self) var injector
    @State private var viewModel: AutoBackupViewModel
    @State private var isShowingFolderPicker = false
    @State private var isShowingCreatePassword = false

    init(viewModel: AutoBackupViewModel) {
        _viewModel = .init(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            switch dataModel.backupPassword {
            case .error:
                authenticateSection(isError: true)
            case .notFetched:
                authenticateSection(isError: false)
            case .notCreated:
                createPasswordSection
            case .fetched:
                enabledSection

                if viewModel.configuration.isEnabled {
                    destinationSection

                    if viewModel.isDestinationConfigured {
                        retentionSection
                        backupNowSection
                    }
                }
            }
        }
        .navigationTitle("Auto-Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
        ) { result in
            // A cancelled picker is not an error worth surfacing; the provider
            // reports any real configuration failure through its own status.
            guard case let .success(url) = result else { return }
            Task {
                await viewModel.configureDestination(url: url)
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(isPresented: $isShowingCreatePassword) {
            NavigationStack {
                BackupKeyChangeView(viewModel: .init(
                    dataModel: dataModel,
                    authenticationService: authenticationService,
                    deriverFactory: injector.vaultKeyDeriverFactory,
                ))
            }
        }
    }

    // MARK: - Authenticate Section

    private func authenticateSection(isError: Bool) -> some View {
        Section {
            ProminentActionButton("Authenticate", systemImage: "key.horizontal.fill") {
                await dataModel.loadBackupPassword()
            }
        } header: {
            Text(isError ? "Authentication Failed" : "Locked")
        } footer: {
            Text(
                isError
                    ? "Unable to verify your identity. Please try again."
                    : "Authenticate to view auto-backup settings.",
            )
            .foregroundStyle(isError ? Color.red : Color.secondary)
        }
    }

    // MARK: - Create Password Section

    private var createPasswordSection: some View {
        Section {
            Button {
                isShowingCreatePassword = true
            } label: {
                FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor) {
                    Text("Create Backup Password")
                }
            }
        } header: {
            Text("Backup Password")
        } footer: {
            Text("Auto-backup needs a backup password before it can run.")
        }
    }

    // MARK: - Enabled Section

    private var enabledSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.configuration.isEnabled },
                set: { enabled in
                    Task {
                        await viewModel.setEnabled(enabled)
                    }
                },
            )) {
                FormRow(image: Image(systemName: viewModel.statusIconName), color: statusColor) {
                    Text("Auto-Backup")
                }
            }

            if case let .error(error) = viewModel.status {
                errorRow(error)
            }
        } footer: {
            Text(viewModel.footerText)
        }
    }

    // MARK: - Destination Section

    private var destinationSection: some View {
        Section {
            if let provider = viewModel.activeProvider, provider.isConfigured {
                Button {
                    changeDestination()
                } label: {
                    LabeledContent {
                        Text("Change")
                    } label: {
                        FormRow(image: Image(systemName: provider.iconSystemName), color: .green) {
                            TextAndSubtitle(title: provider.displayName, subtitle: provider.folderSummary)
                        }
                    }
                }
            } else {
                Button {
                    changeDestination()
                } label: {
                    FormRow(image: Image(systemName: "folder.fill"), color: .accentColor) {
                        Text("Choose Folder")
                    }
                }
            }

            if let error = viewModel.configureError {
                errorRow(error)
            }
        } header: {
            Text("Destination")
        } footer: {
            Text("Backups are saved as encrypted PDFs in a folder you choose.")
        }
    }

    private func changeDestination() {
        Task {
            await viewModel.beginDestinationSelection()
            isShowingFolderPicker = true
        }
    }

    // MARK: - Retention Section

    private var retentionSection: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.configuration.retentionDays },
                set: { retention in
                    Task {
                        await viewModel.setRetention(retention)
                    }
                },
            )) {
                ForEach(AutoBackupRetention.allCases, id: \.self) { retention in
                    Text(retention.localizedTitle).tag(retention)
                }
            } label: {
                FormRow(image: Image(systemName: "clock.arrow.circlepath"), color: .blue) {
                    Text("Keep Backups For")
                }
            }
        }
    }

    // MARK: - Backup Now Section

    /// The row is driven by the service status so that auto-triggered backups show the same
    /// progress as a tap on the button: both are the same operation on the same screen.
    private var backupNowSection: some View {
        Section {
            if let progress = viewModel.backupProgress {
                FormRow(image: Image(systemName: "arrow.clockwise.icloud"), color: .accentColor) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress.phase.localizedTitle)
                        ProgressView(value: progress.fractionCompleted)
                            .animation(.linear(duration: 0.2), value: progress.fractionCompleted)
                    }
                }
            } else if case .cleaningUp = viewModel.status {
                FormRow(image: Image(systemName: "arrow.clockwise.icloud"), color: .accentColor) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cleaning up old backups…")
                        ProgressView(value: 1)
                    }
                }
            } else if viewModel.showsBackupCompleteNotice {
                FormRow(image: Image(systemName: "checkmark.icloud"), color: .green) {
                    Text("Backup Complete")
                }
            } else {
                // Only disable while the tap is in flight: the status row replaces this button as soon as
                // the service reports progress, so the button's own spinner would only flash.
                ProminentActionButton(
                    "Backup Now",
                    systemImage: "arrow.clockwise.icloud",
                    actionOptions: [.disableButton],
                ) {
                    await viewModel.backupNow()
                }
            }
        }
        .animation(.default, value: viewModel.showsBackupCompleteNotice)
    }

    // MARK: - Helpers

    private func errorRow(_ error: AutoBackupError) -> some View {
        FormRow(
            image: Image(systemName: "exclamationmark.triangle.fill"),
            color: .orange,
            alignment: .firstTextBaseline,
        ) {
            TextAndSubtitle(
                title: error.errorDescription ?? "An error occurred",
                subtitle: error.recoverySuggestion,
            )
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .disabled:
            .gray
        case .idle, .completed:
            .green
        case .backingUp, .cleaningUp:
            .accentColor
        case .error:
            .orange
        }
    }
}
