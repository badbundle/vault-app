import SwiftUI
import VaultFeed

/// Shows and edits a private key.
///
/// It's protected as a recovery phrase is: only ever opened after decrypting it with its password, and always opens
/// locked, needing device authentication as well. Once unlocked, the key stays masked until tapped. It's hidden
/// whenever the app isn't in the foreground (so it doesn't appear in the app switcher) or the screen is being recorded
/// or shared, and the item locks again when the app goes to the background. The same covers the editor, whichever
/// step is showing. The key can't be copied, and there's no QR code of it to show.
@MainActor
struct PrivateKeyDetailView: View {
    @State private var viewModel: PrivateKeyDetailViewModel
    @Binding private var navigationPath: NavigationPath

    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @State private var currentError: (any Error)?
    @State private var isShowingDeleteConfirmation = false

    init(
        editingExisting key: PrivateKey,
        encryptionKey: DerivedEncryptionKey,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
        storedMetadata: VaultItem.Metadata,
        editor: any PrivateKeyDetailEditor,
        openInEditMode: Bool,
    ) {
        self.init(
            viewModel: .init(
                mode: .editing(key: key, metadata: storedMetadata, existingKey: encryptionKey),
                dataModel: dataModel,
                editor: editor,
            ),
            navigationPath: navigationPath,
        )
        if openInEditMode {
            viewModel.startEditing()
        }
    }

    init(
        newKeyWithEditor editor: any PrivateKeyDetailEditor,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
    ) {
        self.init(
            viewModel: .init(mode: .creating, dataModel: dataModel, editor: editor),
            navigationPath: navigationPath,
        )
        viewModel.startEditing()
    }

    init(viewModel: PrivateKeyDetailViewModel, navigationPath: Binding<NavigationPath>) {
        _viewModel = .init(initialValue: viewModel)
        _navigationPath = navigationPath
    }

    var body: some View {
        VaultItemDetailView(
            viewModel: viewModel,
            currentError: $currentError,
            isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
            navigationPath: $navigationPath,
            presentationMode: presentationMode,
            editorKind: .privateKey,
            editorIdentity: identity,
            hiddenNotice: isContentHidden ? hiddenNotice : nil,
        ) {
            if viewModel.editingModel.detail.contents.isNotBlank {
                // Encrypted with the key, so it's as private as the key is.
                DetailPageDescriptionSection(title: "Description", text: viewModel.editingModel.detail.contents)
                    .privacySensitive()
            }
            keySection
            DetailPageInfoSections(
                tags: viewModel.tagsThatAreSelected,
                entries: viewModel.detailEntries,
            )
        } editorStep: { step in
            editorStep(step)
        }
        .animation(.snappy, value: isContentHidden)
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background {
                viewModel.lock()
            }
        }
        .onDisappear {
            if !viewModel.isInitialCreation {
                viewModel.isKeyRevealed = false
            }
        }
    }

    /// The key is sensitive enough that it shouldn't be visible in the app switcher, a screen recording or a mirrored
    /// screen.
    private var isContentHidden: Bool {
        scenePhase != .active || isSceneCaptured
    }

    private var hiddenNotice: VaultItemHiddenNotice {
        .init(
            title: "Hidden",
            subtitle: "Private keys are hidden while Vault isn't in the foreground, or while the screen is being recorded or shared.",
        )
    }

    private var identity: DetailEditorItemIdentity {
        DetailEditorItemIdentity(
            systemImage: "key.fill",
            title: viewModel.visibleTitle,
            subtitle: viewModel.editorSummary(for: .content),
            color: viewModel.editingModel.detail.color,
        )
    }

    @ViewBuilder
    private func editorStep(_ step: DetailEditorStep) -> some View {
        switch step {
        case .content:
            PrivateKeyKeyStep(viewModel: viewModel)
        case .details:
            PrivateKeyNameStep(viewModel: viewModel)
        case .appearance:
            DetailEditorAppearanceStep(
                identity: identity,
                color: $viewModel.editingModel.detail.color,
                selectedTags: viewModel.tagsThatAreSelected,
                remainingTags: viewModel.remainingTags,
                tagCountDescription: viewModel.strings.tagCount(tags: viewModel.editingModel.detail.tags.count),
                addTag: { viewModel.editingModel.detail.tags.insert($0.id) },
                removeTag: { viewModel.editingModel.detail.tags.remove($0.id) },
            )
        case .security:
            PrivateKeySecurityStep(viewModel: viewModel)
        }
    }

    // MARK: - Viewing

    /// The key, headed by what it's recognized as: a card with its icon in the validation's color.
    private var keySection: some View {
        let summary = viewModel.validationSummary()
        return Section {
            DetailPageCardLabel(
                title: summary.title,
                subtitle: summary.detail,
                systemImage: summary.systemIconName,
                tint: summary.kind.color,
            )
            .accessibilityElement(children: .combine)
            // The key goes with its heading.
            .listRowSeparator(.hidden)

            PrivateKeyTextView(
                key: viewModel.editingModel.detail.key,
                isRevealed: viewModel.isKeyRevealed,
                toggleRevealed: {
                    withAnimation(.snappy) {
                        viewModel.isKeyRevealed.toggle()
                    }
                },
            )
            .privacySensitive()
            .listRowInsets(EdgeInsets(vertical: 12, horizontal: 12))
        } footer: {
            Text(viewModel.isKeyRevealed ? "Tap the key to hide it." : "Tap the key to reveal it.")
        }
    }
}

/// A private key, masked until revealed. Tapping it reveals or hides it. It's never selectable, so it can't be
/// copied.
struct PrivateKeyTextView: View {
    var key: String
    var isRevealed: Bool
    var toggleRevealed: () -> Void

    /// The same for every key, so the mask doesn't give away how long it is.
    private static let mask = String(repeating: "•", count: 20)

    var body: some View {
        Button(action: toggleRevealed) {
            Text(verbatim: isRevealed ? PrivateKey.displayText(for: key) : Self.mask)
                .font(.callout.monospaced().weight(isRevealed ? .regular : .medium))
                .foregroundStyle(isRevealed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10))
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Private Key"))
        .accessibilityValue(isRevealed ? Text(verbatim: key) : Text("Hidden"))
        .accessibilityHint(isRevealed ? Text("Hides the key") : Text("Reveals the key"))
    }
}

/// Whether a private key is valid, as recognized from its format.
struct PrivateKeyValidationBadge: View {
    var summary: PrivateKeyValidationSummary

    var body: some View {
        // Not a `Label`: at accessibility sizes it lets the title wrap underneath the icon.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: summary.systemIconName)
                .foregroundStyle(summary.kind == .neutral ? Color.secondary : summary.kind.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(summary.detail)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

extension PrivateKeyValidationSummary.Kind {
    var color: Color {
        switch self {
        case .valid: .green
        case .warning: .orange
        case .neutral: .gray
        }
    }
}
