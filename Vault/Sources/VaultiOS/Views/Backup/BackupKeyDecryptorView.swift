import Foundation
import SwiftUI
import VaultFeed

/// Asks for the password a backup was made with, and recreates its key to decrypt it.
///
/// Recreating the key is deliberately slow, so Cancel stays enabled while it runs: with interactive dismissal
/// disabled, it's the way out.
@MainActor
struct BackupKeyDecryptorView: View {
    @State private var viewModel: BackupKeyDecryptorViewModel
    @State private var decryptionTask: Task<Void, Never>?
    @FocusState private var isPasswordFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: BackupKeyDecryptorViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            headerSection
            passwordSection
            decryptSection
        }
        .navigationTitle(Text("Decrypt Backup"))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.isDecrypting || isDecrypted)
        .animation(.snappy, value: viewModel.isDecrypting)
        .animation(.snappy, value: viewModel.decryptionKeyState)
        .sensoryFeedback(.success, trigger: isDecrypted) { _, newValue in
            newValue
        }
        .task {
            // The password is the one thing to enter here, so start typing straight away.
            isPasswordFocused = true
        }
        .task(id: isDecrypted) {
            guard isDecrypted else { return }
            // Long enough to see the lock open. With Reduce Motion, there's nothing to wait for.
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
            }
            dismiss()
        }
        .onChange(of: viewModel.failedAttemptCount) {
            if case let .error(error) = viewModel.decryptionKeyState {
                AccessibilityNotification.Announcement(error.userTitle).post()
            }
            isPasswordFocused = true
        }
        .onDisappear {
            decryptionTask?.cancel()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // Deliberately enabled while the key is recreated: with interactive dismissal disabled, this is
                // the only way out of the up-to-3-minute derivation.
                Button {
                    decryptionTask?.cancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                .tint(.red)
                .disabled(isDecrypted)
            }
        }
    }

    private var isDecrypted: Bool {
        viewModel.decryptionKeyState.isSuccess
    }

    // MARK: - Header Section

    /// The backup password's shield, as on the screen that sets it, which opens once the backup is decrypted.
    private var headerSection: some View {
        Section {
            BackupHeroHeader(
                title: "Enter Backup Password",
                subtitle: "Use the password this backup was made with.",
                systemImage: isDecrypted ? "lock.open.fill" : "lock.shield.fill",
                color: isDecrypted ? .green : .accentColor,
                iconSize: 56,
            )
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        }
    }

    // MARK: - Password Section

    private var passwordSection: some View {
        Section {
            LabeledTextField(
                "Backup Password",
                text: $viewModel.enteredPassword,
                kind: .secure(),
                status: viewModel.decryptionKeyState.isError ? .error() : .none,
            )
            .secretTextInput(.verbatim)
            .focused($isPasswordFocused)
            .submitLabel(.done)
            .onSubmit(decrypt)
            .disabled(viewModel.isDecrypting || isDecrypted)
            .wrongPasswordFeedback(trigger: viewModel.failedAttemptCount)
        }
    }

    // MARK: - Decrypt Section

    private var decryptSection: some View {
        Section {
            ProminentActionButton("Decrypt", systemImage: "lock.open.fill") {
                decrypt()
            }
            .disabled(!viewModel.canAttemptDecryption || viewModel.isDecrypting || isDecrypted)
        } footer: {
            decryptionStatus
        }
    }

    @ViewBuilder
    private var decryptionStatus: some View {
        if viewModel.isDecrypting {
            HStack(alignment: .center, spacing: 4) {
                ProgressView()
                Text("Decrypting the backup. This can take up to 3 minutes.")
            }
        } else if case let .error(error) = viewModel.decryptionKeyState {
            Label(error.userTitle, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func decrypt() {
        guard viewModel.canAttemptDecryption, !viewModel.isDecrypting, !isDecrypted else { return }
        isPasswordFocused = false
        decryptionTask?.cancel()
        decryptionTask = Task {
            await viewModel.attemptDecryption()
        }
    }
}
