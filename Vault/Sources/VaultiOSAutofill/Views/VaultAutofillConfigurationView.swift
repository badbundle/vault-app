import Foundation
import SwiftUI
import VaultiOS

struct VaultAutofillConfigurationView: View {
    @State private var viewModel: VaultAutofillConfigurationViewModel
    init(viewModel: VaultAutofillConfigurationViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            container
                .padding(.vertical, 16)
                .padding(24)
                .containerRelativeFrame([.horizontal, .vertical])
        }
        .containerRelativeFrame([.horizontal, .vertical])
    }

    private var container: some View {
        VStack(alignment: .center, spacing: 32) {
            Spacer()

            VStack(alignment: .center, spacing: 12) {
                Image(systemName: "number.circle.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)

                Text("OTP Autofill")
                    .font(.system(size: 28, weight: .bold))
            }

            VStack(alignment: .center, spacing: 24) {
                Text("Your OTP codes are now available for autofill")
                    .font(.title3)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 16) {
                    featureRow(
                        icon: "network",
                        text: "OTP codes appear on their configured domain names",
                    )

                    featureRow(
                        icon: "arrow.triangle.2.circlepath",
                        text: "Codes update automatically based on your vault items",
                    )
                }
                .frame(maxWidth: 400)
            }

            Spacer()

            Button {
                viewModel.dismiss()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .multilineTextAlignment(.center)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground)),
        )
    }
}
