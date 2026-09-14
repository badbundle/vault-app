import Foundation
import SwiftUI
import VaultFeed
import VaultSettings

struct VaultAboutView: View {
    @State private var viewModel: SettingsViewModel
    private let appVersionText: String

    init(viewModel: SettingsViewModel, appVersionText: String = Bundle.main.vaultAboutVersionText) {
        self.viewModel = viewModel
        self.appVersionText = appVersionText
    }

    var body: some View {
        Form {
            headerSection
            generalSection
            policySection
            mastheadSection
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        PlaceholderView(
            systemIcon: "info.bubble.fill",
            title: "About Vault",
            subtitle: "Vault has been designed from scratch to store your highly sensitive data that you cannot afford to either lose or leak. It's developed in the open and is completely free to use.",
        )
        .padding()
        .containerRelativeFrame(.horizontal)
    }

    private var generalSection: some View {
        Section {
            NavigationLink {
                HelpView(viewModel: viewModel)
            } label: {
                FormRow(
                    image: Image(systemName: "questionmark"),
                    color: .blue,
                ) {
                    Text(viewModel.helpTitle)
                }
            }

            NavigationLink {
                OpenSourceView()
            } label: {
                FormRow(
                    image: Image(systemName: "figure.2.arms.open"),
                    color: .purple,
                ) {
                    Text(viewModel.openSourceTitle)
                }
            }
        }
    }

    private var policySection: some View {
        Section {
            NavigationLink {
                SettingsDocumentView(title: viewModel.termsOfUseTitle, content: TermsOfServiceContent())
            } label: {
                FormRow(
                    image: Image(systemName: "person.fill.checkmark"),
                    color: .green,
                ) {
                    Text(viewModel.termsOfUseTitle)
                }
            }

            NavigationLink {
                SettingsDocumentView(title: viewModel.privacyPolicyTitle, content: PrivacyPolicyContent())
            } label: {
                FormRow(
                    image: Image(systemName: "lock.fill"),
                    color: .red,
                ) {
                    Text(viewModel.privacyPolicyTitle)
                }
            }

            NavigationLink {
                ThirdPartyView()
            } label: {
                FormRow(
                    image: Image(systemName: "text.book.closed.fill"),
                    color: .blue,
                ) {
                    Text(viewModel.thirdPartyTitle)
                }
            }
        }
    }

    private var mastheadSection: some View {
        Section {
            VStack(alignment: .center, spacing: 4) {
                Image("bad-bundle-logo", bundle: VaultFeedAssets.bundle)
                    .resizable(resizingMode: .stretch)
                    .scaledToFit()
                    .frame(height: 22)
                Text("free and open since 2024 ✌️")
                    .font(.caption2)
                Text(appVersionText)
                    .font(.caption2)
                    .padding(.top, 12)
            }
            .padding(.top, 24)
            .containerRelativeFrame(.horizontal)
            .foregroundStyle(.secondary)
            .noListBackground()
        }
    }
}

extension Bundle {
    fileprivate var vaultAboutVersionText: String {
        let marketingVersion = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (marketingVersion, buildNumber) {
        case let (.some(marketingVersion), .some(buildNumber)):
            return "Version \(marketingVersion) (Build \(buildNumber))"
        case let (.some(marketingVersion), .none):
            return "Version \(marketingVersion)"
        case let (.none, .some(buildNumber)):
            return "Build \(buildNumber)"
        case (.none, .none):
            return "Version unavailable"
        }
    }
}
