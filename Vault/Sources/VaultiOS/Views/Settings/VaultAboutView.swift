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
                    image: Image(systemName: "hand.raised.fill"),
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

    /// A plain footnote, worded and styled like the one at the end of GPS's settings, plus its "Open source" line:
    /// Vault is open source, and GPS isn't. The version sits below it.
    private var mastheadSection: some View {
        Section {
            VStack(alignment: .center, spacing: 4) {
                Text("Copyright 2026 Bad Bundle Limited")
                Text("Made in the UK")
                Text("Open source")
                Text(appVersionText)
                    .padding(.top, 12)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 24)
            .containerRelativeFrame(.horizontal)
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
