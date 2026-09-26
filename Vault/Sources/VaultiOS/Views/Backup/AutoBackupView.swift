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
            headerSection

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
                    if viewModel.isDestinationConfigured {
                        settingsSection
                        activitySection
                        backupNowSection
                    } else {
                        chooseFolderSection
                    }
                }
            }
        }
        .navigationTitle("Auto-Backup")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: viewModel.statusHeader)
        .animation(.default, value: viewModel.configuration.isEnabled)
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
            BackupKeyChangeView(viewModel: .init(
                dataModel: dataModel,
                authenticationService: authenticationService,
                deriverFactory: injector.vaultKeyDeriverFactory,
            ))
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

    // MARK: - Header Section

    /// Says plainly whether auto-backup is on and what it's doing, so nobody has to read the toggle
    /// and footers to find out.
    ///
    /// Only once the page is unlocked, though: the live status names the backup folder and describes
    /// errors. Until then, the header just says what auto-backup is, as the Export page does.
    private var headerSection: some View {
        Section {
            if case .fetched = dataModel.backupPassword {
                let header = viewModel.statusHeader
                BackupHeroHeader(
                    title: header.title,
                    subtitle: header.subtitle,
                    systemImage: header.systemImage,
                    color: color(for: header.tone),
                    iconSize: 56,
                )
            } else {
                BackupHeroHeader(
                    title: "Auto-Backup",
                    subtitle: "Saves an encrypted backup of your vault to a folder you choose whenever it changes.",
                    systemImage: "arrow.clockwise.icloud",
                    color: .accentColor,
                    iconSize: 56,
                )
            }
        }
    }

    private func color(for tone: AutoBackupViewModel.StatusHeader.Tone) -> Color {
        switch tone {
        case .off: .secondary
        case .healthy: .green
        case .working: .accentColor
        case .attention: .orange
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
                FormRow(image: Image(systemName: "arrow.clockwise.icloud"), color: .accentColor) {
                    Text("Auto-Backup")
                }
            }
        }
    }

    // MARK: - Choose Folder Section

    private var chooseFolderSection: some View {
        Section {
            ProminentActionButton("Choose Folder", systemImage: "folder.fill", actionOptions: []) {
                changeDestination()
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Backups are saved as encrypted PDFs in a folder you choose, such as one in iCloud Drive.")
                if let error = viewModel.configureError {
                    errorLabel(error)
                }
            }
        }
    }

    // MARK: - Settings Section

    /// What auto-backup is set up to do: where it saves to and how long it keeps backups.
    private var settingsSection: some View {
        Section {
            if let provider = viewModel.activeProvider {
                Button {
                    changeDestination()
                } label: {
                    FormRow(image: Image(systemName: provider.iconSystemName), color: .blue) {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(provider.folderSummary ?? provider.displayName)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        } label: {
                            Text("Save To")
                        }
                    }
                }
                .tint(.primary)
                .accessibilityHint(Text("Choose a different folder"))
            }

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
        } header: {
            Text("Settings")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.scheduleSummary)
                if let error = viewModel.configureError {
                    errorLabel(error)
                }
            }
        }
    }

    private func changeDestination() {
        Task {
            await viewModel.beginDestinationSelection()
            isShowingFolderPicker = true
        }
    }

    // MARK: - Activity Section

    /// The backup that's running, or the result of the last one.
    ///
    /// Driven by the service status so that automatic backups show the same detail as a tap on
    /// Back Up Now: both are the same operation on the same screen.
    private var activitySection: some View {
        Section {
            if let run = viewModel.currentRun {
                AutoBackupProgressView(run: run, destinationName: viewModel.destinationName)
            } else if case .cleaningUp = viewModel.status {
                FormRow(image: Image(systemName: "trash"), color: .accentColor) {
                    HStack {
                        Text("Deleting old backups…")
                        Spacer()
                        ProgressView()
                    }
                }
            } else {
                FormRow(image: Image(systemName: "clock"), color: .blue) {
                    TextAndSubtitle(
                        title: "Last Backup",
                        subtitle: viewModel.lastBackupDate?.formatted(date: .abbreviated, time: .shortened)
                            ?? "No automatic backups yet",
                    )
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(viewModel.currentRun == nil ? "Activity" : "Backing Up")
        }
    }

    // MARK: - Back Up Now Section

    private var backupNowSection: some View {
        Group {
            if viewModel.showsBackupCompleteNotice {
                Section {
                    FormRow(image: Image(systemName: "checkmark.icloud"), color: .green) {
                        Text("Backup Complete")
                    }
                }
            } else if !viewModel.isBackingUp {
                Section {
                    // Only disable while the tap is in flight: the activity section takes over as soon as
                    // the service reports progress, so the button's own spinner would only flash.
                    ProminentActionButton(
                        "Back Up Now",
                        systemImage: "arrow.clockwise.icloud",
                        actionOptions: [.disableButton],
                    ) {
                        await viewModel.backupNow()
                    }
                }
            }
        }
        .animation(.default, value: viewModel.showsBackupCompleteNotice)
    }

    // MARK: - Helpers

    private func errorLabel(_ error: AutoBackupError) -> some View {
        Label {
            Text([error.errorDescription, error.recoverySuggestion].compactMap(\.self).joined(separator: ". "))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
    }
}
