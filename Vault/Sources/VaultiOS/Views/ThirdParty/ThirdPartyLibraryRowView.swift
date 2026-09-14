import SwiftUI
import VaultSettings

struct ThirdPartyLibraryRowView: View {
    var library: ThirdPartyLibrary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(library.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(library.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
