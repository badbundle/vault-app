import Foundation
import SwiftUI
import VaultAppIcon
import VaultFeed

/// Why an item's contents are hidden right now.
struct VaultItemHiddenNotice {
    var title: String
    var subtitle: String
}

/// The basis of a detail view with some of the editing state already bound to buttons etc.
///
/// Shows the item's badge with `contents` beneath it as cards, and while editing, its editor with a step from
/// `editorStep` at a time. The editor's overview starts with the same badge, so Edit and Done change the cards under
/// it rather than the whole page.
///
/// A locked item shows no badge until it's unlocked: the lock stands in for the item, and says no more about it than
/// its tile in the feed does (a note's tile can hide its title).
@MainActor
struct VaultItemDetailView<ChildViewModel: DetailViewModel, ContentsView: View, EditorStepView: View>: View {
    @Bindable var viewModel: ChildViewModel
    @Binding var currentError: (any Error)?
    @Binding var isShowingDeleteConfirmation: Bool
    @Binding var navigationPath: NavigationPath
    var presentationMode: Binding<PresentationMode>?
    var editorKind: DetailEditorItemKind
    var editorIdentity: DetailEditorItemIdentity
    /// Covers everything, the editor included, with a notice that the item is hidden.
    var hiddenNotice: VaultItemHiddenNotice?
    @ViewBuilder var contents: () -> ContentsView
    @ViewBuilder var editorStep: (DetailEditorStep) -> EditorStepView

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
        Group {
            if viewModel.isLocked {
                Form {
                    lockedSection
                }
            } else if let hiddenNotice {
                Form {
                    hiddenSection(hiddenNotice)
                }
            } else if viewModel.isInEditMode {
                DetailEditorView(
                    viewModel: viewModel,
                    kind: editorKind,
                    identity: editorIdentity,
                    delete: viewModel.shouldShowDeleteButton ? { isShowingDeleteConfirmation = true } : nil,
                    stepContent: editorStep,
                )
            } else {
                Form {
                    DetailItemBadgeSection(identity: editorIdentity)
                    contents()
                }
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
            } else if isShowingOpenedEditorStep {
                // A step opened from the editor's overview: back to the overview, which has Cancel and Done.
                backToEditorOverviewItem
                if viewModel.editingModel.isDirty {
                    saveDirtyChangesItem
                }
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

    private var isShowingOpenedEditorStep: Bool {
        viewModel.isInEditMode && viewModel.editorFlow.style == .overview && !viewModel.editorFlow.isShowingOverview
    }

    private func hiddenSection(_ notice: VaultItemHiddenNotice) -> some View {
        Section {
            PlaceholderView(systemIcon: "eye.slash", title: notice.title, subtitle: notice.subtitle)
                .padding()
                .containerRelativeFrame(.horizontal)
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
                ProminentActionButton("Unlock", systemImage: "lock.open.fill") {
                    try await authenticationService.validateAuthentication(reason: "Unlock item")
                    if reduceMotion {
                        viewModel.isLocked = false
                    } else {
                        lockTransition = .unlock
                    }
                }
                .disabled(lockTransition != nil)
            }
        } else if !viewModel.allowsUnlockWithoutDeviceAuthentication {
            // Without device authentication there's no way to unlock this item. It's still there, and can be
            // viewed again once a passcode is set up.
            Section {
                DetailPageCardLabel(
                    title: "Passcode Required",
                    subtitle: "Set up a passcode on this device to view this item.",
                    systemImage: "lock.trianglebadge.exclamationmark.fill",
                    tint: .red,
                )
            }
        } else {
            Section {
                DetailPageCardLabel(
                    title: "No Authentication",
                    subtitle: "This item is not protected due to no authentication being available. Add a passcode to your device to protect this item.",
                    systemImage: "lock.trianglebadge.exclamationmark.fill",
                    tint: .red,
                )
            }

            Section {
                ProminentActionButton("Dismiss", systemImage: "xmark") {
                    viewModel.isLocked = false
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
            case .decrypt, .decryptionFailed, nil:
                // Decrypting belongs to `EncryptedItemDetailView`: here the door only locks and unlocks.
                VaultLockGlyphView(appearance: appearance, metrics: .compact)
            }
        }
        .accessibilityHidden(true)
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

    private var backToEditorOverviewItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                viewModel.goBackInEditor()
            } label: {
                Label("Back", systemImage: "chevron.left")
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
