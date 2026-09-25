import Foundation
import SwiftUI
import VaultFeed
import VaultSettings

/// Everything about the backup password that isn't needed to set one: help pages and the key
/// generation details for this device.
///
/// Pushed from `BackupKeyChangeView`, so the password entry stays the focus of that screen.
@MainActor
struct BackupPasswordDetailsView: View {
    var viewModel: BackupKeyChangeViewModel

    var body: some View {
        Form {
            learnMoreSection
            keyGenerationSection
            #if DEBUG
            debugSection
            #endif
        }
        .navigationTitle(Text("About Backup Passwords"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var learnMoreSection: some View {
        Section {
            HelpQuestionLink(question: "How does the backup password work?") {
                SettingsDocumentView(title: "Backup Passwords", content: BackupPasswordFileContent())
            }
            HelpQuestionLink(question: "What happens when I change it?") {
                SettingsDocumentView(title: "Changing Your Password", content: BackupPasswordChangingFileContent())
            }
            HelpQuestionLink(question: "Are backups secure?") {
                SettingsDocumentView(title: "Backup Security", content: FAQBackupsSecurityFileContent())
            }
        } header: {
            Text("Learn More")
        }
    }

    private var keyGenerationSection: some View {
        Section {
            LabeledContent {
                Text(viewModel.encryptionKeyDeriverSignature.userVisibleDescription)
            } label: {
                Text("Algorithm")
            }

            LabeledContent {
                Text(viewModel.encryptionKeyDeriverSignature.id)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
            } label: {
                Text("ID")
            }
        } header: {
            Text("Key Generation")
        } footer: {
            Text("How this device turns your password into an encryption key.")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            AsyncButton {
                await viewModel.loadExistingPassword()
            } label: {
                Text("Fetch Existing Password")
            } loading: {
                ProgressView()
            }
        } header: {
            Text("Debug")
        }
    }
    #endif
}
