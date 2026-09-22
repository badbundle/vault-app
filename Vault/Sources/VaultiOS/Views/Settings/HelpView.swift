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
            question("What is a 'code'?") {
                SettingsDocumentView(title: "About Codes", content: FAQCodesFileContent())
            }
            question("Can I encrypt individual items?") {
                SettingsDocumentView(title: "Item Encryption", content: FAQItemEncryptionFileContent())
            }
            question("Why should I make backups?") {
                SettingsDocumentView(title: "About Backups", content: FAQBackupsGeneralFileContent())
            }
            question("Are backups secure?") {
                SettingsDocumentView(title: "Backup Security", content: FAQBackupsSecurityFileContent())
            }
            question("How do I move items to another device?") {
                SettingsDocumentView(title: "Moving Between Devices", content: FAQSyncDevicesFileContent())
            }
        }
    }

    private func question(_ title: String, @ViewBuilder destination: () -> some View) -> some View {
        NavigationLink {
            destination()
        } label: {
            FormRow(image: Image(systemName: "questionmark.circle"), color: .blue, style: .standard) {
                Text(title)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HelpView(viewModel: SettingsViewModel())
    }
}
