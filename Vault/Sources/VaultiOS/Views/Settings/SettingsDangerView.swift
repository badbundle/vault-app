import Foundation
import SwiftUI
import Toasts
import VaultFeed

/// The Danger Zone: a bottom sheet that explains what deleting all data removes and what it keeps, then asks
/// "Delete everything?" in a step that slides in before device authentication.
///
/// Sized to fit like the New Item picker, and it can't be dismissed while deleting. Deleting all data is the only
/// action here (MANIFESTO C1, C4).
struct SettingsDangerView: View {
    @State private var viewModel: SettingsDangerViewModel
    @State private var displayedStep: Step
    @State private var direction: Direction = .forward
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentToast) private var presentToast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step: Hashable {
        case overview
        case confirmation
    }

    private enum Direction {
        case forward
        case backward
    }

    init(viewModel: SettingsDangerViewModel) {
        _viewModel = State(initialValue: viewModel)
        _displayedStep = State(initialValue: viewModel.isShowingConfirmation ? .confirmation : .overview)
    }

    var body: some View {
        // Scrolls only when the largest text sizes make a step taller than the sheet can be.
        ScrollView {
            ZStack(alignment: .top) {
                stepContent
                    .id(displayedStep)
                    .transition(transition)
            }
            .padding(.horizontal, 20)
            // Room above the title for the drag indicator.
            .padding(.top, 28)
            .padding(.bottom, 8)
            .fittedSheet()
        }
        .scrollBounceBehavior(.basedOnSize)
        .interactiveDismissDisabled(viewModel.isDeleting)
        .onChange(of: viewModel.isShowingConfirmation) { _, isShowingConfirmation in
            direction = isShowingConfirmation ? .forward : .backward
            // A separate update, so the outgoing step has already taken on the new direction when it leaves.
            Task { @MainActor in
                withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .snappy(duration: 0.4)) {
                    displayedStep = isShowingConfirmation ? .confirmation : .overview
                }
                // VoiceOver moves to the new step, as it would for a new screen.
                AccessibilityNotification.ScreenChanged().post()
            }
        }
        .onChange(of: viewModel.state) { _, state in
            guard state == .deleted else { return }
            presentToast(ToastValue(icon: Image(systemName: "checkmark"), message: "Vault Deleted"))
            dismiss()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch displayedStep {
        case .overview: overview
        case .confirmation: confirmation
        }
    }

    private var transition: AnyTransition {
        if reduceMotion {
            .opacity
        } else {
            switch direction {
            case .forward: .push(from: .trailing)
            case .backward: .push(from: .leading)
            }
        }
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(
                title: "Danger Zone",
                message: "Deleting your data can't be undone. If you might need it again, back it up first.",
            )

            VStack(alignment: .leading, spacing: 16) {
                DeletionOutcomeList(
                    title: "Deleted from this device",
                    systemImage: "minus.circle.fill",
                    color: .red,
                    items: [
                        "Every code, note and recovery phrase",
                        "All your tags",
                        "Codes suggested by AutoFill",
                    ],
                )
                DeletionOutcomeList(
                    title: "Kept",
                    systemImage: "checkmark.circle.fill",
                    color: .green,
                    items: [
                        "Backups you've saved, as PDFs or auto-backups",
                        "Your backup password",
                        "Auto-backup and app settings",
                    ],
                )
            }

            Button {
                viewModel.askToConfirm()
            } label: {
                OptionCardLabel(
                    title: "Delete All Data",
                    subtitle: "You'll be asked to confirm.",
                    systemImage: "trash.fill",
                    color: .red,
                )
                .optionCardBackground()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Confirmation

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(
                title: "Delete everything?",
                message: "Every code, note, recovery phrase and tag on this device will be erased. You can't undo this.",
            )

            if case let .failed(error) = viewModel.state {
                DeletionErrorLabel(error: error)
                    .transition(.opacity)
            }

            ConfirmationActions(
                isDeleting: viewModel.isDeleting,
                goBack: { viewModel.cancelConfirmation() },
                delete: { Task { await viewModel.deleteEntireVault() } },
            )
        }
        .animation(.default, value: viewModel.state)
    }
}

/// One side of what deleting all data does: a heading, then a row per kind of data with the same symbol.
private struct DeletionOutcomeList: View {
    var title: String
    var systemImage: String
    var color: Color
    var items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            ForEach(items, id: \.self) { item in
                Label {
                    Text(item)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Why deleting didn't happen, above the buttons so trying again is right there.
private struct DeletionErrorLabel: View {
    var error: PresentationError

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(error.userTitle)
                    .fontWeight(.semibold)
                if let description = error.userDescription {
                    Text(description)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.subheadline)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Back to the overview, and on to delete everything: laid out like the editor's action bar, with the delete button
/// in red.
private struct ConfirmationActions: View {
    var isDeleting: Bool
    var goBack: () -> Void
    var delete: () -> Void

    @ScaledMetric(relativeTo: .body) private var buttonHeight: Double = 50

    var body: some View {
        HStack(spacing: 12) {
            if !isDeleting {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: buttonHeight - 16, height: buttonHeight - 16)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Back")
                .transition(.scale.combined(with: .opacity))
            }

            Button(role: .destructive, action: delete) {
                ProminentActionLabel("Delete Everything", systemImage: "trash.fill", isLoading: isDeleting)
                    .frame(minHeight: buttonHeight - 16)
            }
            .prominentActionButton()
            // Not disabled while deleting, which would grey it out: the view model ignores a second tap.
            .allowsHitTesting(!isDeleting)
            // The label hides under the spinner while deleting, so say what's happening instead.
            .accessibilityLabel(isDeleting ? "Deleting everything" : "Delete Everything")
        }
        .animation(.snappy, value: isDeleting)
    }
}

#Preview {
    @Previewable @State var isPresented = true

    Color.clear
        .sheet(isPresented: $isPresented) {
            SettingsDangerView(viewModel: .init(
                dataModel: VaultDataModel(
                    vaultStore: VaultStoreStub(),
                    vaultTagStore: VaultTagStoreStub(),
                    vaultImporter: VaultStoreImporterMock(),
                    vaultDeleter: VaultStoreDeleterMock(),
                    vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
                    vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
                    backupPasswordStore: BackupPasswordStoreMock(),
                    killphraseKeyStore: KillphraseKeyStoreMock(),
                    killphraseRehashService: nil,
                    searchPassphraseKeyStore: SearchPassphraseKeyStoreMock(),
                    searchPassphraseRehashService: nil,
                    backupEventLogger: BackupEventLoggerMock(),
                ),
                authenticationService: .init(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            ))
        }
}
