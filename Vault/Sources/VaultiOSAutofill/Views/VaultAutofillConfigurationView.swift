import Foundation
import SwiftUI
import VaultiOS

struct VaultAutofillConfigurationView: View {
    @State private var viewModel: VaultAutofillConfigurationViewModel
    init(viewModel: VaultAutofillConfigurationViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        List {
            headerSection
            featuresSection
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.dismiss()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .center, spacing: 12) {
                Image(systemName: "number.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)

                Text("OTP Autofill")
                    .font(.title.bold())

                Text("Your OTP codes are now available for autofill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            .listRowSeparator(.hidden)
        }
    }

    private var featuresSection: some View {
        Section {
            featureRow(
                icon: "network",
                text: "OTP codes appear on their configured domain names",
            )

            featureRow(
                icon: "arrow.triangle.2.circlepath",
                text: "Codes update automatically based on your vault items",
            )
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
        }
    }
}
