import Foundation
import SwiftUI
import VaultFeed

@MainActor
struct EncryptedItemPreviewView: View {
    var viewModel: EncryptedItemPreviewViewModel
    var behaviour: VaultItemViewBehaviour

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon - small and subtle at top
            Image(systemName: "lock.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isEditing ? .white.opacity(0.8) : viewModel.color.color.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

            VaultCardTitle(text: viewModel.visibleTitle, isEditing: isEditing)

            Spacer()

            // Encrypted label at bottom
            Text("Encrypted")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isEditing ? .white.opacity(0.6) : .secondary.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .shimmering(active: isEditing)
        .modifier(
            VaultCardModifier(
                configuration: .init(
                    style: isEditing ? .prominent : .secondary,
                    border: viewModel.color.color,
                    padding: .init(),
                ),
            ),
        )
    }

    private var isEditing: Bool {
        switch behaviour {
        case .normal: false
        case .editingState: true
        }
    }
}

#Preview {
    EncryptedItemPreviewView(
        viewModel: .init(title: "Hello", color: .tagDefault, previewMode: .titleAndFirstLine),
        behaviour: .normal,
    )
    .frame(width: 200, height: 200)
    .padding()
}

#Preview {
    EncryptedItemPreviewView(
        viewModel: .init(
            title: "Hello Hello Hello Hello Hello Hello Hello",
            color: .tagDefault,
            previewMode: .titleAndFirstLine,
        ),
        behaviour: .normal,
    )
    .frame(width: 200, height: 200)
    .padding()
}

#Preview {
    EncryptedItemPreviewView(
        viewModel: .init(title: "Hello", color: .tagDefault, previewMode: .hidden),
        behaviour: .normal,
    )
    .frame(width: 200, height: 200)
    .padding()
}
