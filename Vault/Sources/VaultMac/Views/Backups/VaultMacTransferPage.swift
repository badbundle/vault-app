import SwiftUI
import VaultFeed

/// Move to Another Device: the whole vault, encrypted with the backup password, as QR codes for an iPhone or iPad
/// to scan (G54). Nothing is saved. The codes stop, and are forgotten, when the page closes or Vault locks.
struct VaultMacTransferPage: View {
    @State var viewModel: DeviceTransferExportViewModel

    var body: some View {
        VStack(spacing: 20) {
            switch viewModel.state {
            case .idle, .generating, .completed:
                ProgressView("Preparing the codes…")
            case let .displayingQR(currentIndex, totalCount):
                Text("On your iPhone or iPad, open Vault, go to Backups, then Restore, and scan these codes.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                if let image = viewModel.currentQRCodeImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360, maxHeight: 360)
                        .padding(16)
                        .background(.white, in: .rect(cornerRadius: 12))
                        .accessibilityLabel("Transfer code \(currentIndex + 1) of \(totalCount)")
                        .accessibilityIdentifier("backups.transfer.code")
                }
                Text("Showing \(currentIndex + 1) of \(totalCount). They change every 2 seconds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            case let .error(error):
                VaultMacBackupNotice(
                    systemImage: "exclamationmark.triangle",
                    title: error.userTitle,
                    message: error.userDescription ?? "",
                    action: ("Try Again", { Task { await viewModel.generateShards() } }),
                )
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if viewModel.state == .idle {
                await viewModel.generateShards()
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
