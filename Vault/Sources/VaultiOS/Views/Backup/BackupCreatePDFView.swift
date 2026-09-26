import Foundation
import PDFKit
import SwiftUI
import VaultFeed

/// Step one of a PDF backup: choose the options and create the PDF.
///
/// Says up front that the PDF still has to be saved afterwards, so creating it doesn't read as the end.
@MainActor
struct BackupCreatePDFView: View {
    typealias ViewModel = BackupCreatePDFViewModel
    @State private var viewModel: ViewModel
    @Binding private var navigationPath: NavigationPath

    init(viewModel: BackupCreatePDFViewModel, navigationPath: Binding<NavigationPath>) {
        _viewModel = .init(initialValue: viewModel)
        _navigationPath = navigationPath
    }

    var body: some View {
        Form {
            headerSection
            optionsSection
            createSection
        }
        .navigationTitle(Text("PDF Backup"))
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(viewModel.generatedPDFPublisher(), perform: { value in
            navigationPath.append(value)
        })
    }

    private var headerSection: some View {
        Section {
            BackupHeroHeader(
                title: "Create a PDF Backup",
                subtitle: "Your vault is encrypted into a PDF of QR codes. Once it's created, you'll save it to Files or print it.",
                systemImage: "doc.text.fill",
                color: .accentColor,
                iconSize: 56,
            ) {
                PDFBackupStepsView(progress: .creating)
                    .padding(.top, 4)
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Picker(selection: $viewModel.size) {
                ForEach(ViewModel.Size.allCases) { format in
                    Text(format.localizedTitle)
                        .tag(format)
                }
            } label: {
                FormRow(image: Image(systemName: "newspaper.fill"), color: .accentColor, style: .standard) {
                    Text("Paper Size")
                }
            }

            LabeledTextField(
                "Password Hint",
                text: $viewModel.userHint,
                kind: .multiline(minLines: 3),
            )
        } header: {
            Text("Options")
        } footer: {
            Text("An optional hint printed on the document to help you remember its password.")
        }
    }

    private var createSection: some View {
        Section {
            ProminentActionButton("Create PDF", systemImage: "doc.text.fill") {
                await viewModel.createPDF()
            }
        } footer: {
            if case let .error(presentationError) = viewModel.state {
                Text(presentationError.userDescription ?? presentationError.userTitle)
                    .foregroundStyle(.red)
            }
        }
    }
}
