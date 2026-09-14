import Foundation
import SwiftUI
import VaultSettings

struct OpenSourceView: View {
    var body: some View {
        Form {
            headerSection
            aboutSection
            linkSection
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        PlaceholderView(
            systemIcon: "figure.2.arms.open",
            title: OpenSourceStrings.title,
        )
        .padding()
        .containerRelativeFrame(.horizontal)
    }

    private var aboutSection: some View {
        Section {
            Text(OpenSourceStrings.aboutOpenSource)
            Text(OpenSourceStrings.aboutPrivacy)
        }
        .foregroundStyle(.secondary)
    }

    private var linkSection: some View {
        Section {
            Link(destination: OpenSourceStrings.openSourceLink) {
                FormRow(image: Image(systemName: "chevron.left.forwardslash.chevron.right"), color: .purple) {
                    Text(OpenSourceStrings.aboutLink)
                }
            }
        }
    }
}

#Preview {
    OpenSourceView()
}
