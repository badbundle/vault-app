import Foundation
import SwiftUI

/// Temporary view to use when there is no content with: icon, title, description.
struct PlaceholderView<Icon: View>: View {
    var title: String
    var subtitle: String?
    /// Drawn at `.largeTitle` size; a system image by default.
    @ViewBuilder var icon: () -> Icon

    @ScaledMetric(relativeTo: .largeTitle) private var iconHeight: Double = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            icon()
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

extension PlaceholderView where Icon == Image {
    init(systemIcon: String, title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            Image(systemName: systemIcon)
        }
    }
}

#Preview {
    Form {
        PlaceholderView(systemIcon: "checkmark", title: "Hello World", subtitle: "This is the subtitle for this view")
            .containerRelativeFrame(.horizontal)
    }
}
