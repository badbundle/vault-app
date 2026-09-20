import Foundation
import SwiftUI
import VaultAppIcon
import VaultFeed

/// The basis of a detail view with some of the editing state already bound to buttons etc.
@MainActor
struct VaultItemDetailView<ChildViewModel: DetailViewModel, ContentsView: View>: View {
    @Bindable var viewModel: ChildViewModel
    @Binding var currentError: (any Error)?
    @Binding var isShowingDeleteConfirmation: Bool
    @Binding var navigationPath: NavigationPath
    var presentationMode: Binding<PresentationMode>?
    @ViewBuilder var contents: () -> ContentsView

    @Environment(DeviceAuthenticationService.self) private var authenticationService: DeviceAuthenticationService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isError = false
    /// What the vault door in the locked section is doing. `.lock` plays when a
    /// save has just locked the item; `.unlock` once the user has authenticated,
    /// with the contents taking over as the bolts release.
    @State private var lockTransition: VaultLockTransition?
    @State private var lockClickCount = 0

    private func dismiss() {
        presentationMode?.wrappedValue.dismiss()
    }

    var body: some View {
        Form {
            if viewModel.isLocked {
                lockedSection
            } else {
                contents()
            }
        }
        .navigationTitle(viewModel.strings.title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.editingModel.isDirty)
        .animation(.snappy, value: viewModel.isInEditMode)
        .sensoryFeedback(.impact(weight: .heavy), trigger: lockClickCount)
        .onChange(of: viewModel.isLocked) { wasLocked, isLocked in
            // Locked by a save: show the door being shut, so the lock is seen to
            // work. Also clears any unlock that played before this re-lock.
            if isLocked, !wasLocked {
                lockTransition = reduceMotion ? nil : .lock
            }
        }
        .onReceive(viewModel.isFinishedPublisher()) {
            dismiss()
        }
        .onReceive(viewModel.didEncounterErrorPublisher()) { error in
            currentError = error
            isError = true
        }
        .confirmationDialog(
            viewModel.strings.deleteConfirmTitle,
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button(viewModel.strings.deleteItemTitle, role: .destructive) {
                Task { await viewModel.delete() }
            }
        } message: {
            Text(viewModel.strings.deleteConfirmSubtitle)
        }
        .alert(localized(key: "action.error.title"), isPresented: $isError, presenting: currentError) { _ in
            Button(localized(key: "action.error.confirm.title"), role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .toolbar {
            if viewModel.isLocked {
                cancelImmediatelyItem
            } else {
                // Only if this view is the root of the navigation stack should we show these actions.
                // If it isn't, it implies going back to the original context is more likely the correct
                // action to take.
                if navigationPath.isEmpty {
                    if viewModel.isInitialCreation {
                        cancelCreationItem
                    } else {
                        if viewModel.editingModel.isDirty {
                            cancelEditsItem
                        } else if !viewModel.isInEditMode {
                            startEditingItem
                        }
                    }
                }

                if viewModel.editingModel.isDirty {
                    saveDirtyChangesItem
                } else {
                    // Don't show the "done" item during initial creation if not dirty
                    // The only option should be to cancel.
                    if !viewModel.isInitialCreation {
                        doneItem
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var lockedSection: some View {
        if authenticationService.canAuthenticate {
            Section {
                PlaceholderView(title: "Item Locked", subtitle: "Unlock this item to view its contents.") {
                    lockGlyph
                }
                .padding()
                .containerRelativeFrame(.horizontal)
            }

            Section {
                AsyncButton {
                    try await authenticationService.validateAuthentication(reason: "Unlock item")
                    if reduceMotion {
                        viewModel.isLocked = false
                    } else {
                        lockTransition = .unlock
                    }
                } label: {
                    unlockRow {
                        Text("Unlock")
                            .foregroundStyle(Color.accentColor)
                    }
                } loading: {
                    unlockRow {
                        ProgressView()
                    }
                }
                .disabled(lockTransition != nil)
            }
        } else {
            Section {
                FormRow(
                    image: Image(systemName: "lock.trianglebadge.exclamationmark.fill"),
                    color: .red,
                    style: .standard,
                ) {
                    VStack(alignment: .leading) {
                        Text("No authentication")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text(
                            "This item is not protected due to no authentication being available. Add a passcode to your device to protect this item.",
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    viewModel.isLocked = false
                } label: {
                    FormRow(image: Image(systemName: "xmark.circle.fill"), color: .accentColor) {
                        Text("Dismiss")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    /// The padlock of the locked section is the vault door from the app icon. At
    /// rest it sits shut. When a save has just locked the item the door swings
    /// shut and the wheel spins to seat; when the user authenticates the wheel
    /// spins the other way and the contents come in on the click (at this size
    /// the door swinging open afterwards would only be a wait).
    @ViewBuilder
    private var lockGlyph: some View {
        let appearance: VaultAppIconAppearance = colorScheme == .dark ? .dark : .light
        Group {
            switch lockTransition {
            case .lock:
                VaultLockAnimationView(
                    transition: .lock,
                    appearance: appearance,
                    metrics: .compact,
                    onClick: { lockClickCount += 1 },
                    onFinished: { lockTransition = nil },
                )
            case .unlock:
                VaultLockAnimationView(
                    transition: .unlock,
                    appearance: appearance,
                    metrics: .compact,
                    onClick: {
                        lockClickCount += 1
                        withAnimation(.snappy) {
                            viewModel.isLocked = false
                        }
                    },
                )
            case nil:
                VaultLockGlyphView(appearance: appearance, metrics: .compact)
            }
        }
        .accessibilityHidden(true)
    }

    private func unlockRow(@ViewBuilder content: @escaping () -> some View) -> some View {
        FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor, content: content)
    }

    private var cancelCreationItem: some ToolbarContent {
        // This button always dismisses immediately (without saving) if it's the initial creation.
        // (Dirty or not!)
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Text(viewModel.strings.cancelEditsTitle)
                    .tint(.red)
            }
        }
    }

    private var cancelEditsItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                viewModel.done()
            } label: {
                Text(viewModel.strings.cancelEditsTitle)
                    .tint(.red)
            }
        }
    }

    private var startEditingItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                viewModel.startEditing()
            } label: {
                Text(viewModel.strings.startEditingTitle)
                    .tint(.accentColor)
            }
        }
    }

    private var saveDirtyChangesItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            AsyncButton {
                await viewModel.saveChanges()
            } label: {
                Text(viewModel.strings.saveEditsTitle)
                    .tint(.accentColor)
            } loading: {
                ProgressView()
            }
            .disabled(!viewModel.editingModel.isValid)
        }
    }

    private var doneItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button {
                viewModel.done()
            } label: {
                Text(viewModel.strings.doneEditingTitle)
                    .tint(.accentColor)
            }
        }
    }

    private var cancelImmediatelyItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                // Bypass view model state and just dismiss the view right now.
                dismiss()
            } label: {
                Text(viewModel.strings.cancelEditsTitle)
                    .tint(.red)
            }
        }
    }
}
