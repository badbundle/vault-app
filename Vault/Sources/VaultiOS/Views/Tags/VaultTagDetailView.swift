import Foundation
import SwiftUI
import VaultFeed

@MainActor
struct VaultTagDetailView: View {
    @State private var viewModel: VaultTagDetailViewModel
    @State private var selectedColor: Color

    @Environment(\.dismiss) private var dismiss

    init(viewModel: VaultTagDetailViewModel) {
        self.viewModel = viewModel
        _selectedColor = State(initialValue: viewModel.currentTag.color.color)
    }

    var body: some View {
        Form {
            tagNameSection
            styleSection

            if viewModel.isExistingItem {
                deleteSection
            }
        }
        .navigationTitle(viewModel.strings.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.isDirty {
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton {
                        await viewModel.save()
                        dismiss()
                    } label: {
                        Text("Save")
                    } loading: {
                        ProgressView()
                    }
                    .disabled(!viewModel.isValidToSave)
                }
            }

            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .foregroundStyle(.red)
                }
            }
        }
        .onChange(of: selectedColor.hashValue) { _, _ in
            viewModel.currentTag.color = VaultItemColor(color: selectedColor)
        }
    }

    private var tagNameSection: some View {
        Section {
            TextField("My Tag", text: $viewModel.currentTag.name)
        } header: {
            Text("Name")
        }
    }

    private var styleSection: some View {
        Section {
            ColorPicker("Color", selection: $selectedColor)

            NavigationLink {
                IconPickerView(
                    selectedIcon: $viewModel.currentTag.iconName,
                    iconOptions: viewModel.systemIconOptions,
                    selectedColor: selectedColor,
                )
            } label: {
                HStack {
                    Text("Icon")
                    Spacer()
                    Image(systemName: viewModel.currentTag.iconName)
                        .foregroundStyle(selectedColor)
                }
            }
        } header: {
            Text("Style")
        }
    }

    private var deleteSection: some View {
        Section {
            AsyncButton {
                await viewModel.delete()
                dismiss()
            } label: {
                deleteRow {
                    Text("Delete Tag")
                        .foregroundStyle(Color.red)
                }
            } loading: {
                deleteRow {
                    ProgressView()
                }
            }
        }
    }

    private func deleteRow(@ViewBuilder content: @escaping () -> some View) -> some View {
        FormRow(image: Image(systemName: "trash.fill"), color: .red, content: content)
    }
}

// MARK: - Icon Picker View

@MainActor
private struct IconPickerView: View {
    @Binding var selectedIcon: String
    let iconOptions: [String]
    let selectedColor: Color

    var body: some View {
        List {
            ForEach(iconOptions, id: \.self) { icon in
                Button {
                    selectedIcon = icon
                } label: {
                    HStack {
                        Image(systemName: icon)
                            .foregroundStyle(selectedIcon == icon ? selectedColor : .secondary)
                            .frame(width: 30)
                        Spacer()
                        if selectedIcon == icon {
                            Image(systemName: "checkmark")
                                .foregroundStyle(selectedColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Choose Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}
