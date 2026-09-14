import Foundation
import SwiftUI

/// Temporary view to use when there is no content with: icon, title, description.
struct PlaceholderView: View {
    var systemIcon: String
    var title: String
    var subtitle: String?

    @ScaledMetric(relativeTo: .largeTitle) private var iconHeight: Double = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: systemIcon)
                .font(.largeTitle)
                .foregroundStyle(.primary)
                .frame(height: iconHeight, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textCase(.none)
        .multilineTextAlignment(.leading)
        .listRowSeparator(.hidden)
    }
}

#Preview {
    Form {
        PlaceholderView(systemIcon: "checkmark", title: "Hello World", subtitle: "This is the subtitle for this view")
            .containerRelativeFrame(.horizontal)
    }
}
