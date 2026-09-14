import Foundation
import SwiftUI
import UIKit
import VaultFeed

@MainActor
struct DeviceTransferExportView: View {
    @State private var viewModel: DeviceTransferExportViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: DeviceTransferExportViewModel) {
        _viewModel = .init(initialValue: viewModel)
    }

    var body: some View {
        Form {
            section
        }
        .navigationTitle(Text("Transfer to Device"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                }
            }
        }
        .onAppear {
            if case .idle = viewModel.state {
                Task {
                    await viewModel.generateShards()
                }
            }
        }
    }

    @ViewBuilder
    private var section: some View {
        switch viewModel.state {
        case .idle, .generating:
            generatingSection
        case let .displayingQR(currentIndex, totalCount):
            displayingSection(currentIndex: currentIndex, totalCount: totalCount)
        case let .error(presentationError):
            errorSection(presentationError)
        case .completed:
            completedSection
        }
    }

    private var generatingSection: some View {
        Section {
            PlaceholderView(
                systemIcon: "gearshape.fill",
                title: "Generating QR Codes",
                subtitle: "Preparing your vault data for transfer...",
            )
            .padding()
            .containerRelativeFrame(.horizontal)
        }
    }

    private func displayingSection(currentIndex: Int, totalCount: Int) -> some View {
        Section {
            qrCodeDisplay

            progressInfo(currentIndex: currentIndex, totalCount: totalCount)
        } footer: {
            Text("Point your other device's camera at the QR codes. They will cycle automatically every 2 seconds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var qrCodeDisplay: some View {
        VStack(spacing: 16) {
            if let image = viewModel.currentQRCodeImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 300, maxHeight: 300)
                    .padding()
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 100))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 300, maxHeight: 300)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func progressInfo(currentIndex: Int, totalCount: Int) -> some View {
        VStack(spacing: 12) {
            Text("Showing \(currentIndex + 1) of \(totalCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            BackupImportCodeStateVisualizerView(
                totalCount: totalCount,
                selectedIndexes: Set([currentIndex]),
            )
            .padding(.horizontal)
        }
    }

    private func errorSection(_ presentationError: PresentationError) -> some View {
        Section {
            PlaceholderView(
                systemIcon: "exclamationmark.triangle.fill",
                title: presentationError.userTitle,
                subtitle: presentationError.userDescription ?? "An error occurred.",
            )
            .padding()
            .containerRelativeFrame(.horizontal)

            Button {
                Task {
                    await viewModel.generateShards()
                }
            } label: {
                FormRow(image: Image(systemName: "arrow.clockwise"), color: .accentColor) {
                    Text("Try Again")
                }
            }
        }
    }

    private var completedSection: some View {
        Section {
            PlaceholderView(
                systemIcon: "checkmark.circle.fill",
                title: "Transfer Complete",
                subtitle: "Your vault has been prepared for transfer.",
            )
            .padding()
            .containerRelativeFrame(.horizontal)
        }
    }
}
