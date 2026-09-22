import Foundation
import SwiftUI
import VaultSettings

struct OpenSourceView: View {
    var body: some View {
        Form {
            headerSection
            linkSection
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        PlaceholderView(
            systemIcon: "figure.2.arms.open",
            title: OpenSourceStrings.title,
            subtitle: OpenSourceStrings.about,
        )
        .padding()
        .containerRelativeFrame(.horizontal)
    }

    private var linkSection: some View {
        Section {
            Link(destination: OpenSourceStrings.openSourceLink) {
                HStack {
                    Text(OpenSourceStrings.viewOnGitHub)
                    Image(systemName: "arrow.up.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .noListBackground()
        }
    }
}

#Preview {
    NavigationStack {
        OpenSourceView()
    }
}
