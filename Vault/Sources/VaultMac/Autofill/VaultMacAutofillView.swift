import SwiftUI
import VaultFeed

/// The AutoFill sheet: the lock, then the codes to fill, with the same search as iOS AutoFill, which never checks
/// killphrases (G2).
struct VaultMacAutofillView: View {
    @State var model: VaultMacAutofillModel
    var previews: VaultMacItemPreviews
    /// Fills the code into the app that asked.
    var fill: (String) -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 420, height: 480)
        .task {
            await model.prepareToUnlock()
            await model.appLock.unlock()
        }
        .onChange(of: model.appLock.isLocked) { _, isLocked in
            if !isLocked {
                Task { await model.loadCodes() }
            }
        }
        .onChange(of: model.dataModel.itemsSearchQuery) {
            Task { await model.loadCodes() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.availability {
        case .checking:
            ProgressView()
        case let .needsTheApp(reason):
            VaultMacBackupNotice(systemImage: "lock.shield", title: "Open Vault", message: Self.message(for: reason))
        case .available:
            if case let .locked(state) = model.appLock.state {
                VaultMacLockView(
                    state: state,
                    unlock: { await model.appLock.unlock() },
                    unlockWithPassword: { await model.appLock.unlock(password: $0) },
                )
            } else {
                codes
            }
        }
    }

    private var codes: some View {
        VStack(spacing: 0) {
            VaultMacSearchField(text: Bindable(model.dataModel).itemsSearchQuery, focusRequest: 0)
                .padding()
            List(model.codes) { item in
                if let preview = previews.code(for: item) {
                    VaultMacAutofillCodeRow(item: item, preview: preview) { code in
                        fill(code)
                    }
                }
            }
            .overlay {
                if model.codes.isEmpty {
                    ContentUnavailableView(
                        model.dataModel.isSearching ? "No Results" : "No Codes",
                        systemImage: "key.horizontal",
                    )
                }
            }
            .accessibilityIdentifier("autofill.codes")
        }
    }

    static func message(for reason: VaultMacAutofillModel.NeedsTheAppReason) -> String {
        switch reason {
        case .notSetUp:
            "Open Vault on this Mac and set its App Lock Password first."
        case .notEnoughMemory:
            "There isn't enough memory to open your vault here. Open Vault instead."
        case .unavailable:
            "Vault is busy with your vault right now. Open Vault, then try again."
        }
    }
}

/// A code in the sheet: clicking it fills its current code.
private struct VaultMacAutofillCodeRow: View {
    var item: VaultItem
    var preview: OTPCodePreviewViewModel
    var fill: (String) -> Void

    var body: some View {
        Button {
            if let action = preview.pasteboardCopyText, !action.requiresAuthenticationToCopy {
                fill(action.text)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.issuer.isBlank ? "Unnamed Code" : preview.issuer)
                        .font(.headline)
                    if preview.accountName.isNotEmpty {
                        Text(preview.accountName)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VaultMacOTPCodeText(state: preview.code, font: .title3.weight(.semibold))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("autofill.code")
    }
}
