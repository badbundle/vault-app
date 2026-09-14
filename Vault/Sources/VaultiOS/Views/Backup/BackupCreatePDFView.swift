import Foundation
import PDFKit
import SwiftUI
import VaultFeed

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
            optionsSection
            createSection
        }
        .navigationTitle(Text("Create PDF"))
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(viewModel.generatedPDFPublisher(), perform: { value in
            navigationPath.append(value)
        })
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

            TextEditor(text: $viewModel.userHint)
                .font(.callout)
                .frame(minHeight: 150)
                .keyboardType(.default)
                .listRowInsets(EdgeInsets())
        } header: {
            Text("Options")
        } footer: {
            Text("An optional hint printed on the document to help you remember its password.")
        }
    }

    private var createSection: some View {
        Section {
            AsyncButton {
                await viewModel.createPDF()
            } label: {
                FormRow(image: Image(systemName: "checkmark.circle.fill"), color: .accentColor) {
                    Text("Make PDF")
                }
            } loading: {
                FormRow(image: Image(systemName: "checkmark.circle.fill"), color: .accentColor) {
                    ProgressView()
                }
            }
        } footer: {
            if case let .error(presentationError) = viewModel.state {
                Text(presentationError.userDescription ?? presentationError.userTitle)
                    .foregroundStyle(.red)
            }
        }
    }
}
