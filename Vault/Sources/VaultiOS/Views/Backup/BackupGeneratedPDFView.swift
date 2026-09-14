import Foundation
import PDFKit
import SwiftUI
import VaultFeed

struct BackupGeneratedPDFView: View {
    typealias ViewModel = BackupCreatePDFViewModel
    private let pdf: ViewModel.GeneratedPDF
    private let dismiss: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var selectedPageIndex: Int?

    private let previewTargetWidth = 120.0

    init(pdf: ViewModel.GeneratedPDF, dismiss: @escaping () -> Void) {
        self.pdf = pdf
        self.dismiss = dismiss
    }

    var body: some View {
        Form {
            pdfPreviewSection
            exportSection
        }
        .navigationTitle(Text("PDF"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .foregroundStyle(Color.accentColor)
                }
            }
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

    private struct PDFPageSelection: Identifiable {
        let index: Int
        let document: PDFDocument
        let totalPages: Int
        var id: Int {
            index
        }
    }

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
                    }
                    Spacer(minLength: 2)
                }
                .padding(.vertical, 16)
            }
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Generated Document Preview")
        }
    }

    private var exportSection: some View {
        Section {
            ShareLink(item: pdf.diskURL, subject: .init("Vault Export")) {
                FormRow(image: Image(systemName: "square.and.arrow.up.fill"), color: .accentColor) {
                    Text("Export & Save")
                }
            }
        } footer: {
            Text("Make sure you export and save the PDF, or your data will not be backed up.")
                .foregroundStyle(.red)
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
