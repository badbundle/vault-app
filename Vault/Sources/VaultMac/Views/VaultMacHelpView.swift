import FoundationExtensions
import MarkdownUI
import Observation
import SwiftUI
import VaultCore
import VaultSettings

/// The pages of the Help window: the iOS app's FAQ, then the policies, libraries and open source.
enum VaultMacHelpPage: String, CaseIterable, Identifiable, Hashable {
    case codes
    case itemEncryption
    case backups
    case backupSecurity
    case movingBetweenDevices
    case duress
    case termsOfUse
    case privacyPolicy
    case libraries
    case openSource

    var id: Self {
        self
    }

    static let questions: [VaultMacHelpPage] = [
        .codes, .itemEncryption, .backups, .backupSecurity, .movingBetweenDevices, .duress,
    ]
    static let about: [VaultMacHelpPage] = [.termsOfUse, .privacyPolicy, .libraries, .openSource]

    var title: String {
        let titles = SettingsViewModel()
        return switch self {
        case .codes: "What is a 'code'?"
        case .itemEncryption: "Can I encrypt individual items?"
        case .backups: "Why should I make backups?"
        case .backupSecurity: "Are backups secure?"
        case .movingBetweenDevices: "How do I move items to another device?"
        case .duress: "What's a duress password?"
        case .termsOfUse: titles.termsOfUseTitle
        case .privacyPolicy: titles.privacyPolicyTitle
        case .libraries: titles.thirdPartyTitle
        case .openSource: titles.openSourceTitle
        }
    }

    /// The page's text, from the app's resources, as iOS shows it.
    var document: FormattedString? {
        let content: (any FileBackedContent)? = switch self {
        case .codes: FAQCodesFileContent()
        case .itemEncryption: FAQItemEncryptionFileContent()
        case .backups: FAQBackupsGeneralFileContent()
        case .backupSecurity: FAQBackupsSecurityFileContent()
        case .movingBetweenDevices: FAQSyncDevicesFileContent()
        case .duress: FAQDuressFileContent()
        case .termsOfUse: TermsOfServiceContent()
        case .privacyPolicy: PrivacyPolicyContent()
        case .libraries, .openSource: nil
        }
        return content?.loadContent()
    }
}

/// Which Help page is open, so the About window can open the Help window at one.
@MainActor
@Observable
final class VaultMacHelpModel {
    var selection: VaultMacHelpPage? = .codes
}

/// The Help window (⌘?): the FAQ, the policies, the libraries Vault uses and where its source is. Nothing in it
/// comes from the vault.
struct VaultMacHelpView: View {
    @Bindable var model: VaultMacHelpModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Questions") {
                    ForEach(VaultMacHelpPage.questions) { page in
                        title(page)
                    }
                }
                Section("About Vault") {
                    ForEach(VaultMacHelpPage.about) { page in
                        title(page)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 300)
        } detail: {
            if let page = model.selection {
                VaultMacHelpPageView(page: page)
                    .id(page)
            } else {
                ContentUnavailableView("Vault Help", systemImage: "questionmark.circle")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    /// A page's title in the sidebar, wrapping onto a second line rather than being cut off where the sidebar is
    /// narrower than it.
    private func title(_ page: VaultMacHelpPage) -> some View {
        Text(page.title)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .tag(page)
    }
}

/// One Help page.
struct VaultMacHelpPageView: View {
    var page: VaultMacHelpPage

    @State private var libraries: [ThirdPartyLibrary]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(page.title)
                    .font(.largeTitle.bold())
                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("help.page")
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .libraries:
            librariesList
        case .openSource:
            Text(OpenSourceStrings.about)
            Link(OpenSourceStrings.viewOnGitHub, destination: OpenSourceStrings.openSourceLink)
        default:
            switch page.document {
            case let .markdown(markdown):
                Markdown(MarkdownContent(markdown.content))
                    .markdownImagesNeverLoad()
                    .textSelection(.enabled)
            case let .raw(text):
                Text(text)
                    .textSelection(.enabled)
            case nil:
                Text("This page couldn't be loaded.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var librariesList: some View {
        if let libraries {
            Text("Thank you to all third-party software developers!")
                .foregroundStyle(.secondary)
            ForEach(libraries) { library in
                VStack(alignment: .leading, spacing: 6) {
                    Link(library.name, destination: library.url)
                        .font(.headline)
                    Text(library.licence)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Divider()
            }
        } else {
            ProgressView()
                .task {
                    let attribution = try? await Attribution.parse(resourceFetcher: FileSystemLocalResourceFetcher())
                    libraries = attribution?.libraries ?? []
                }
        }
    }
}
