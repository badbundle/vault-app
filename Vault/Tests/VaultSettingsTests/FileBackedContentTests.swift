import Foundation
import Testing
import VaultCore
@testable import VaultSettings

struct FileBackedContentTests {
    @Test
    func loadContent_loadsEveryMarkdownDocument() {
        let documents: [any FileBackedContent] = [
            FAQCodesFileContent(),
            FAQBackupsGeneralFileContent(),
            FAQBackupsSecurityFileContent(),
            FAQItemEncryptionFileContent(),
            FAQSyncDevicesFileContent(),
            BackupPasswordFileContent(),
            BackupPasswordChangingFileContent(),
            PrivacyPolicyContent(),
            TermsOfServiceContent(),
        ]

        for document in documents {
            guard case let .markdown(markdown) = document.loadContent() else {
                Issue.record("\(document.fileName) didn't load as Markdown")
                continue
            }
            #expect(!markdown.content.isEmpty, "\(document.fileName) is empty")
        }
    }
}
