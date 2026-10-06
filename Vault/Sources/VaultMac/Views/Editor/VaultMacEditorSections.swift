import Combine
import SwiftUI
import VaultFeed

/// The colors an item can be, as the iOS app offers them.
enum VaultMacItemColors {
    static let palette: [(name: String, color: VaultItemColor)] = [
        ("Gray", .default),
        ("Red", .init(red: 1, green: 0.22, blue: 0.24)),
        ("Orange", .init(red: 1, green: 0.55, blue: 0.16)),
        ("Yellow", .init(red: 1, green: 0.8, blue: 0)),
        ("Green", .init(red: 0.2, green: 0.78, blue: 0.35)),
        ("Mint", .init(red: 0, green: 0.78, blue: 0.75)),
        ("Cyan", .init(red: 0, green: 0.75, blue: 0.95)),
        ("Blue", .init(red: 0, green: 0.53, blue: 1)),
        ("Indigo", .init(red: 0.38, green: 0.33, blue: 0.96)),
        ("Purple", .init(red: 0.8, green: 0.4, blue: 0.95)),
        ("Pink", .init(red: 1, green: 0.18, blue: 0.47)),
        ("Brown", .init(red: 0.67, green: 0.52, blue: 0.37)),
    ]
}

/// An item's color and tags.
struct VaultMacAppearanceSection: View {
    @Binding var color: VaultItemColor?
    @Binding var tags: Set<Identifier<VaultItemTag>>
    var allTags: [VaultItemTag]

    var body: some View {
        Section("Appearance") {
            Picker("Color", selection: Binding(get: { color ?? .default }, set: { color = $0 })) {
                ForEach(VaultMacItemColors.palette, id: \.name) { swatch in
                    Text(swatch.name).tag(swatch.color)
                }
            }
            if allTags.isNotEmpty {
                LabeledContent("Tags") {
                    VStack(alignment: .leading) {
                        ForEach(allTags) { tag in
                            Toggle(tag.name, isOn: Binding(
                                get: { tags.contains(tag.id) },
                                set: { isOn in
                                    if isOn {
                                        tags.insert(tag.id)
                                    } else {
                                        tags.remove(tag.id)
                                    }
                                },
                            ))
                        }
                    }
                }
            }
        }
    }
}

/// What an item's Privacy & Security offers, set per item only (C1, C8, C9): locking it, hiding it behind a search
/// passphrase, and a killphrase. Nothing here says which other items have any of them (C5).
struct VaultMacPrivacySection: View {
    @Binding var viewConfig: VaultItemViewConfiguration
    @Binding var searchPassphrase: String
    var hasExistingSearchPassphrase: Bool
    @Binding var killphraseEnabled: Bool
    @Binding var newKillphrase: String
    /// `nil` where the item is always locked, as a recovery phrase is.
    var lockState: Binding<VaultItemLockState>?

    var body: some View {
        Section {
            if let lockState {
                Toggle("Lock with Touch ID or Mac Password", isOn: Binding(
                    get: { lockState.wrappedValue.isLocked },
                    set: { lockState.wrappedValue = $0 ? .lockedWithNativeSecurity : .notLocked },
                ))
                .accessibilityIdentifier("editor.lock")
            }
            Picker("Visibility", selection: $viewConfig) {
                Text("Always Shown").tag(VaultItemViewConfiguration.alwaysVisible)
                Text("Hidden Until Searched For").tag(VaultItemViewConfiguration.requiresSearchPassphrase)
            }
            if viewConfig == .requiresSearchPassphrase {
                VaultMacSecureField(
                    hasExistingSearchPassphrase ? "New Search Passphrase (optional)" : "Search Passphrase",
                    text: $searchPassphrase, identifier: "editor.search-passphrase",
                )
            }
            Toggle("Killphrase", isOn: $killphraseEnabled)
            if killphraseEnabled {
                VaultMacSecureField("Killphrase", text: $newKillphrase, identifier: "editor.killphrase")
            }
        } header: {
            Text("Privacy & Security")
        } footer: {
            Text(
                "A hidden item only shows while the whole search is its passphrase. Searching for a killphrase deletes the item at once.",
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

/// The buttons along the bottom of an editor: Delete for an item that exists, and Cancel and Save.
struct VaultMacEditorButtons: View {
    var canSave: Bool
    var isSaving: Bool
    var deleteConfirmation: (title: String, message: String)?
    var cancel: () -> Void
    var save: () async -> Void
    var delete: () async -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        HStack {
            if let deleteConfirmation {
                Button("Delete…", role: .destructive) {
                    isConfirmingDelete = true
                }
                .confirmationDialog(deleteConfirmation.title, isPresented: $isConfirmingDelete) {
                    Button("Delete", role: .destructive) {
                        Task { await delete() }
                    }
                } message: {
                    Text(deleteConfirmation.message)
                }
                .accessibilityIdentifier("editor.delete")
            }
            Spacer()
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave || isSaving)
            .accessibilityIdentifier("editor.save")
        }
        .padding()
    }
}

extension View {
    /// Says what went wrong when an editor's save or delete fails, leaving the editor open with its changes.
    func vaultMacEditorErrorAlert(_ errors: AnyPublisher<any Error, Never>) -> some View {
        modifier(VaultMacEditorErrorAlert(errors: errors))
    }
}

private struct VaultMacEditorErrorAlert: ViewModifier {
    var errors: AnyPublisher<any Error, Never>
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .onReceive(errors) { error in
                message = error.localizedDescription
            }
            .alert(
                "Something Went Wrong",
                isPresented: Binding(get: { message != nil }, set: {
                    if !$0 {
                        message = nil
                    }
                }),
            ) {
                Button("OK") {}
            } message: {
                Text(message ?? "")
            }
    }
}

/// A new password for an item, typed twice. It only counts once both agree.
struct VaultMacNewPassword: Equatable {
    var password = ""
    var confirmation = ""

    /// What's saved: the password once it's confirmed, and nothing until then.
    var confirmed: String {
        password == confirmation ? password : ""
    }

    /// Whether the editor can save: nothing's typed, or the same password is typed twice.
    var agrees: Bool {
        password.isEmpty || password == confirmation
    }
}
