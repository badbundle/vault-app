import Foundation
import SwiftUI
import VaultSettings

struct HelpView: View {
    var viewModel: SettingsViewModel

    var body: some View {
        Form {
            headerSection
            questionsSection
        }
        .navigationTitle(Text(viewModel.helpTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        PlaceholderView(
            systemIcon: "questionmark.bubble.fill",
            title: viewModel.helpTitle,
            subtitle: "Answers to common questions about how Vault works.",
        )
        .padding()
        .containerRelativeFrame(.horizontal)
    }

    private var questionsSection: some View {
        Section {
            HelpQuestionLink(question: "What is a 'code'?") {
                SettingsDocumentView(title: "About Codes", content: FAQCodesFileContent())
            }
            HelpQuestionLink(question: "Can I encrypt individual items?") {
                SettingsDocumentView(title: "Item Encryption", content: FAQItemEncryptionFileContent())
            }
            HelpQuestionLink(question: "Why should I make backups?") {
                SettingsDocumentView(title: "About Backups", content: FAQBackupsGeneralFileContent())
            }
            HelpQuestionLink(question: "Are backups secure?") {
                SettingsDocumentView(title: "Backup Security", content: FAQBackupsSecurityFileContent())
            }
            HelpQuestionLink(question: "How do I move items to another device?") {
                SettingsDocumentView(title: "Moving Between Devices", content: FAQSyncDevicesFileContent())
            }
        }
    }
}

#Preview {
    NavigationStack {
        HelpView(viewModel: SettingsViewModel())
    }
}
