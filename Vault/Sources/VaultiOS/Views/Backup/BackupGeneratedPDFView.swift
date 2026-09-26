import Foundation
import PDFKit
import SwiftUI
import VaultFeed

/// Step two of a PDF backup: save the PDF that was just created.
struct BackupGeneratedPDFView: View {
    private let pdf: BackupCreatePDFViewModel.GeneratedPDF
    private let dismiss: () -> Void

    @Environment(VaultInjector.self) private var injector

    init(pdf: BackupCreatePDFViewModel.GeneratedPDF, dismiss: @escaping () -> Void) {
        self.pdf = pdf
        self.dismiss = dismiss
    }

    var body: some View {
        BackupSavePDFView(
            viewModel: .init(pdf: pdf, backupEventLogger: injector.backupEventLogger),
            dismiss: dismiss,
        )
    }
}

/// Makes saving the PDF the one thing to do, and warns before leaving without it: until it's saved,
/// printed or sent somewhere, the PDF is only a temporary file and the vault isn't backed up.
struct BackupSavePDFView: View {
    @State private var viewModel: BackupGeneratedPDFViewModel
    private let dismiss: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var selectedPageIndex: Int?
    @State private var isSharing = false
    @State private var isConfirmingLeave = false

    private let previewTargetWidth = 120.0

    init(viewModel: BackupGeneratedPDFViewModel, dismiss: @escaping () -> Void) {
        _viewModel = .init(initialValue: viewModel)
        self.dismiss = dismiss
    }

    private var pdf: BackupCreatePDFViewModel.GeneratedPDF {
        viewModel.pdf
    }

    var body: some View {
        Form {
            headerSection
            saveSection
            pdfPreviewSection
        }
        .navigationTitle(Text("PDF Backup"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    leave()
                } label: {
                    Text("Done")
                }
            }
        }
        .confirmationDialog(
            Text("Your Backup Isn't Saved"),
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible,
        ) {
            Button("Save or Print Backup") {
                isSharing = true
            }
            Button("Leave Without Saving", role: .destructive) {
                dismiss()
            }
        } message: {
            Text(
                "The PDF only exists in Vault until you save, print or send it. If you leave now, your vault isn't backed up.",
            )
        }
        .shareSheet(isPresented: $isSharing, items: [pdf.diskURL]) { completed in
            viewModel.shareSheetFinished(completed: completed)
        }
        .animation(.default, value: viewModel.isSaved)
        .sensoryFeedback(.success, trigger: viewModel.isSaved) { _, isSaved in
            isSaved
        }
        .fullScreenCover(item: Binding(
            get: { selectedPageIndex.map { PDFPageSelection(
                index: $0,
                document: pdf.document,
                totalPages: pdf.document.pageCount,
            ) } },
            set: { selectedPageIndex = $0?.index },
        )) { selection in
            if let page = pdf.document.page(at: selection.index) {
                PDFPageViewerView(
                    page: page,
                    pageIndex: selection.index,
                    pageCount: selection.totalPages,
                )
            }
        }
        .interactiveDismissDisabled()
        .navigationBarBackButtonHidden()
    }

    private func leave() {
        if viewModel.isSaved {
            dismiss()
        } else {
            isConfirmingLeave = true
        }
    }

    private struct PDFPageSelection: Identifiable {
        let index: Int
        let document: PDFDocument
        let totalPages: Int
        var id: Int {
            index
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            if viewModel.isSaved {
                BackupHeroHeader(
                    title: "Backup Saved",
                    subtitle: "Keep it somewhere safe. You'll need your backup password to restore it.",
                    systemImage: "checkmark.circle.fill",
                    color: .green,
                    iconSize: 56,
                    bouncesOnAppear: true,
                ) {
                    PDFBackupStepsView(progress: .done)
                        .padding(.top, 4)
                }
            } else {
                BackupHeroHeader(
                    title: "Save Your Backup",
                    subtitle: "Your PDF is ready, but it isn't saved anywhere yet. Save it to Files, print it or send it somewhere safe to finish your backup.",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange,
                    iconSize: 56,
                ) {
                    PDFBackupStepsView(progress: .saving)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Save

    @ViewBuilder
    private var saveSection: some View {
        if viewModel.isSaved {
            Section {
                ProminentActionButton("Done", systemImage: "checkmark", actionOptions: []) {
                    dismiss()
                }
            }

            Section {
                Button {
                    isSharing = true
                } label: {
                    FormRow(
                        image: Image(systemName: "square.and.arrow.up"),
                        color: .accentColor,
                        style: .standard,
                    ) {
                        Text("Save Another Copy")
                    }
                }
            } footer: {
                Text("Keeping copies in two places, like Files and on paper, protects you if one is lost.")
            }
        } else {
            Section {
                ProminentActionButton("Save or Print Backup", systemImage: "square.and.arrow.up", actionOptions: []) {
                    isSharing = true
                }
            } footer: {
                Text("Save it to Files or iCloud Drive, print a paper copy, or AirDrop it to another device.")
            }
        }
    }

    // MARK: - Preview

    private var pdfPreviewSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 12) {
                    Spacer(minLength: 2)
                    ForEach(0 ..< pdf.document.pageCount, id: \.self) { pageIndex in
                        thumbnail(pageIndex: pageIndex)?
                            .resizable(resizingMode: .stretch)
                            .aspectRatio(pdf.size.aspectRatio, contentMode: .fit)
                            .frame(width: previewTargetWidth)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .shadow(radius: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(.secondary.opacity(0.2), lineWidth: 1),
                            )
                            .onTapGesture {
                                selectedPageIndex = pageIndex
                            }
                            .accessibilityElement()
                            .accessibilityLabel(Text("Page \(pageIndex + 1) of \(pdf.document.pageCount)"))
                            .accessibilityAddTraits(.isButton)
                    }
                    Spacer(minLength: 2)
                }
                .padding(.vertical, 16)
            }
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Preview")
        } footer: {
            Text("Tap a page to see it full size.")
        }
    }

    private func thumbnail(pageIndex: Int) -> Image? {
        let pageAspectRatio = pdf.size.aspectRatio
        let devicePreviewSize = displayScale * previewTargetWidth
        let scaledSize = CGSize(width: devicePreviewSize, height: devicePreviewSize / pageAspectRatio)
        let page = pdf.document.page(at: pageIndex)
        guard let uiimage = page?.thumbnail(of: scaledSize, for: .trimBox) else { return nil }
        return Image(uiImage: uiimage)
    }
}
