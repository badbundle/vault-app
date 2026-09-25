import Foundation
import SwiftUI
import VaultFeed

@MainActor
struct VaultTagDetailView: View {
    @State private var viewModel: VaultTagDetailViewModel
    @State private var selectedColor: Color
    @State private var isShowingDeleteConfirmation = false

    @Environment(\.dismiss) private var dismiss

    init(viewModel: VaultTagDetailViewModel) {
        self.viewModel = viewModel
        _selectedColor = State(initialValue: viewModel.currentTag.color.color)
    }

    var body: some View {
        Form {
            nameSection
            iconSection

            if viewModel.isExistingItem {
                deleteSection
            }
        }
        .navigationTitle(viewModel.strings.title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.isDirty)
        .toolbar {
            if viewModel.isDirty {
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton {
                        await viewModel.save()
                        if viewModel.saveError == nil {
                            dismiss()
                        }
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
        .confirmationDialog(
            viewModel.strings.deleteConfirmTitle,
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button(viewModel.strings.deleteItemTitle, role: .destructive) {
                Task {
                    await viewModel.delete()
                    if viewModel.deleteError == nil {
                        dismiss()
                    }
                }
            }
        } message: {
            Text(viewModel.strings.deleteConfirmSubtitle)
        }
        .alert(
            currentError?.userTitle ?? localized(key: "action.error.title"),
            isPresented: isShowingError,
            presenting: currentError,
        ) { _ in
            Button(localized(key: "action.error.confirm.title"), role: .cancel) {}
        } message: { error in
            if let description = error.userDescription {
                Text(description)
            }
        }
        .onChange(of: selectedColor.hashValue) { _, _ in
            viewModel.currentTag.color = VaultItemColor(color: selectedColor)
        }
    }

    private var currentError: PresentationError? {
        viewModel.saveError ?? viewModel.deleteError
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            currentError != nil
        } set: { isShowing in
            if !isShowing {
                viewModel.clearErrors()
            }
        }
    }

    /// The tag as the rest of the app will show it, updating as it's edited,
    /// above the colour picker. Mirrors the icon-and-colour header used by
    /// the item detail editors.
    private var previewHeader: some View {
        VStack(spacing: 10) {
            TagPillView(tag: viewModel.previewTag)
                // Only echoes the name field, icon grid and colour picker,
                // which VoiceOver already reads.
                .accessibilityHidden(true)

            ColorPicker(selection: $selectedColor, supportsOpacity: false, label: {
                EmptyView()
            })
            .labelsHidden()
        }
        .textCase(nil)
    }

    private var nameSection: some View {
        Section {
            TextField("My Tag", text: $viewModel.currentTag.name)
        } header: {
            previewHeader
                .containerRelativeFrame(.horizontal)
                .padding(.vertical, 2)
                .padding(.bottom, 4)
        }
    }

    private var iconSection: some View {
        Section {
            IconGridPicker(
                selectedIcon: $viewModel.currentTag.iconName,
                iconOptions: viewModel.systemIconOptions,
                selectedColor: viewModel.currentTag.color.badgeColor,
            )
        } header: {
            Text("Icon")
        }
    }

    private var deleteSection: some View {
        Section {
            ProminentActionButton(
                localized(key: "action.delete.title"),
                systemImage: "trash.fill",
                role: .destructive,
            ) {
                isShowingDeleteConfirmation = true
            }
        }
    }
}

// MARK: - Icon Grid Picker

/// Inline grid of selectable SF Symbols. The selected icon is drawn like the
/// tag's badge, so it matches how the tag appears everywhere else.
private struct IconGridPicker: View {
    @Binding var selectedIcon: String
    let iconOptions: [String]
    let selectedColor: Color

    @ScaledMetric(relativeTo: .body) private var cellSize: Double = 44

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize), spacing: 8)], spacing: 8) {
            ForEach(iconOptions, id: \.self) { icon in
                let isSelected = selectedIcon == icon
                Button {
                    selectedIcon = icon
                } label: {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .frame(width: cellSize, height: cellSize)
                        .background(
                            isSelected ? selectedColor : Color(.tertiarySystemFill),
                            in: .circle,
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
