import SwiftUI
import VaultCore
import VaultFeed

/// A code's page: its site and account, its live code to copy, and for a counter-based code, Next Code.
struct VaultMacOTPDetailView: View {
    var item: VaultItem
    var code: OTPAuthCode
    var tags: [VaultItemTag]

    @Environment(\.vaultMacItemPreviews) private var previews
    @Environment(\.vaultMacCopy) private var copy
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(code.data.issuer.isBlank ? "Unnamed Code" : code.data.issuer)
                    .font(.largeTitle.bold())
                if code.data.accountName.isNotEmpty {
                    Text(code.data.accountName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            if let viewModel = previews?.code(for: item) {
                codeBox(viewModel)
            }
            if item.metadata.userDescription.isNotEmpty {
                VaultMacDetailField(title: "Description") {
                    Text(item.metadata.userDescription)
                }
            }
            VaultMacDetailFooter(metadata: item.metadata, tags: tags)
        }
    }

    private func codeBox(_ viewModel: OTPCodePreviewViewModel) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VaultMacOTPCodeText(state: viewModel.code, font: .system(size: 40, weight: .semibold))
                .accessibilityIdentifier("detail.code")
            if let timer = previews?.timer(for: item) {
                VaultMacCodeTimer(state: timer, size: 22)
            }
            Spacer()
            if case let .hotp(counter) = code.type,
               let incrementer = previews?.incrementer(item.id, .init(counter: counter, data: code.data))
            {
                Button("Next Code") {
                    Task { try? await incrementer.incrementCounter() }
                }
                .disabled(!incrementer.isButtonEnabled)
            }
            Button(didCopy ? "Copied" : "Copy Code") {
                Task { await copyCode(viewModel) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(viewModel.pasteboardCopyText == nil)
            .accessibilityIdentifier("detail.copy")
        }
        .padding(16)
        .background(.quinary, in: .rect(cornerRadius: 12))
    }

    private func copyCode(_ viewModel: OTPCodePreviewViewModel) async {
        guard let action = viewModel.pasteboardCopyText, let copy, await copy(action) else { return }
        didCopy = true
        try? await Task.sleep(for: .seconds(1.5))
        didCopy = false
    }
}
