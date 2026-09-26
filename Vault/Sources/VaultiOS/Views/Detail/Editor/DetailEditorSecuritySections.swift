import Foundation
import SwiftUI
import VaultFeed

// The sections that make up the editor's privacy and security step. Each kind of item uses the ones it has, with
// wording for that kind of item.

/// Hiding an item from the feed until its passphrase is searched for.
struct DetailEditorVisibilitySection: View {
    @Binding var viewConfig: VaultItemViewConfiguration
    @Binding var passphrase: String
    var passphraseValidation: FieldValidationState
    /// With a passphrase already set, the field can be left empty to keep it.
    var hasExistingPassphrase: Bool
    /// What hiding the item does, for this kind of item.
    var explanation: String
    /// A warning about what hiding the item means, shown while it's hidden.
    var hiddenWarning: String

    var body: some View {
        Section {
            Toggle(isOn: $viewConfig.isEnabled) {
                FormRow(image: Image(systemName: viewConfig.systemIconName), color: .accentColor, style: .standard) {
                    Text("Hide with Passphrase")
                }
            }

            if viewConfig.isEnabled {
                LabeledTextField(
                    hasExistingPassphrase ? "New Passphrase" : "Passphrase",
                    text: $passphrase,
                    prompt: hasExistingPassphrase ? "Leave empty to keep the current one" : nil,
                    status: .init(errorFrom: passphraseValidation),
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
            }
        } header: {
            Text("Visibility")
        } footer: {
            Text(viewConfig.isEnabled ? hiddenWarning : explanation)
        }
    }
}

/// Requiring device authentication to see the item.
struct DetailEditorLockSection: View {
    @Binding var lockState: VaultItemLockState
    /// What locking does, for this kind of item.
    var explanation: String

    var body: some View {
        Section {
            Toggle(isOn: $lockState.isLocked) {
                FormRow(image: Image(systemName: lockState.systemIconName), color: .accentColor, style: .standard) {
                    Text("Lock")
                }
            }
        } footer: {
            Text(explanation)
        }
    }
}

/// A secret phrase that deletes the item when it's searched for.
///
/// The phrase is only ever stored as a digest, so there's nothing to show once it's set: the field is only for
/// setting a new one, and left empty it keeps the one there is.
///
/// What a killphrase does is only explained once it's turned on, as it was when it had a sheet of its own to open:
/// someone flipping through the editor shouldn't be told how the feature works (MANIFESTO C9).
struct DetailEditorKillphraseSection: View {
    @Binding var isEnabled: Bool
    @Binding var newKillphrase: String
    var isValid: Bool
    /// With a killphrase already set, the field can be left empty to keep it.
    var hasExistingKillphrase: Bool
    /// What a killphrase does, for this kind of item.
    var explanation: String
    /// A warning about searching.
    var enabledWarning: String

    var body: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                FormRow(
                    image: Image(systemName: isEnabled ? "bolt.badge.checkmark.fill" : "bolt"),
                    color: .accentColor,
                    style: .standard,
                ) {
                    Text("Killphrase")
                }
            }

            if isEnabled {
                LabeledTextField(
                    "New Killphrase",
                    text: $newKillphrase,
                    prompt: hasExistingKillphrase ? "Leave empty to keep the current one" : nil,
                    status: isValid ? .none : .error(message: "Enter some text, not just spaces."),
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
            }
        } footer: {
            if isEnabled {
                Text(explanation + "\n\n" + enabledWarning)
            }
        }
        .onChange(of: isEnabled) { _, isEnabled in
            if !isEnabled {
                newKillphrase = ""
            }
        }
    }
}

/// What the item's tile shows in the feed.
struct DetailEditorPreviewModeSection: View {
    @Binding var previewMode: NotePreviewMode
    /// An encrypted item can't show its first line, which is encrypted.
    var isEncrypted: Bool
    var explanation: String

    private var availableModes: [NotePreviewMode] {
        if isEncrypted {
            NotePreviewMode.allCases.filter { $0 != .titleAndFirstLine }
        } else {
            NotePreviewMode.allCases
        }
    }

    var body: some View {
        Section {
            Picker(selection: $previewMode) {
                ForEach(availableModes, id: \.self) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            } label: {
                FormRow(image: Image(systemName: "rectangle.dashed"), color: .accentColor, style: .standard) {
                    Text("Preview")
                }
            }
        } footer: {
            Text(explanation)
        }
        .onAppear(perform: keepPreviewModeAvailable)
        .onChange(of: isEncrypted) { _, _ in
            keepPreviewModeAvailable()
        }
    }

    private func keepPreviewModeAvailable() {
        if !availableModes.contains(previewMode) {
            previewMode = availableModes.first ?? .titleOnly
        }
    }
}

/// Encrypting the item with a password, which is set in its own sheet: the password is only applied once it's
/// been confirmed.
struct DetailEditorEncryptionSection<Editor: View>: View {
    var title: String
    /// The row's value: whether the item is encrypted, or what's needed.
    var status: String
    var isStatusWarning: Bool
    var explanation: String
    @ViewBuilder var editor: () -> Editor

    @State private var isShowingEditor = false

    var body: some View {
        Section {
            Button {
                isShowingEditor = true
            } label: {
                FormRow(image: Image(systemName: "lock.iphone"), color: .accentColor, style: .standard) {
                    LabeledContent(title) {
                        Text(status)
                            .foregroundStyle(isStatusWarning ? Color.red : Color.secondary)
                    }
                    .font(.body)
                }
            }
        } footer: {
            Text(explanation)
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                editor()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                isShowingEditor = false
                            } label: {
                                Text("Done")
                            }
                        }
                    }
            }
        }
    }
}
