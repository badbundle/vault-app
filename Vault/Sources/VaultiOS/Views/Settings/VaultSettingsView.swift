import SwiftUI
import VaultFeed
import VaultSettings

/// The app's settings, one section per group.
///
/// Every section has a heading and a short footer, so each reads as a card of its own. Rows are
/// single-line `FormRow`s with a prominent icon in their section's `SettingsIconColor`, so they're all the same
/// height whether they hold a toggle, a picker or a button. The Danger Zone stays last.
@MainActor
struct VaultSettingsView: View {
    @Environment(VaultDataModel.self) private var dataModel
    @Environment(DeviceAuthenticationService.self) private var authenticationService
    @State private var viewModel: SettingsViewModel
    @Bindable private var localSettings: LocalSettings

    @State private var modal: Modal?

    private enum Modal: IdentifiableSelf {
        case danger
    }

    init(viewModel: SettingsViewModel, localSettings: LocalSettings) {
        _viewModel = State(wrappedValue: viewModel)
        _localSettings = Bindable(wrappedValue: localSettings)
    }

    var body: some View {
        Form {
            clipboardSection
            universalClipboardSection
            dangerSection
        }
        // A little more room than the default between sections, so a footer doesn't run into the next heading.
        .listSectionSpacing(.custom(28))
        .navigationTitle(viewModel.title)
        .sheet(item: $modal, onDismiss: nil) { item in
            switch item {
            case .danger:
                NavigationStack {
                    SettingsDangerView(viewModel: .init(
                        dataModel: dataModel,
                        authenticationService: authenticationService,
                    ))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Done")
                            }
                        }
                    }
                }
            }
        }
    }

    private var clipboardSection: some View {
        Section {
            Picker(selection: $localSettings.state.pasteTimeToLive) {
                ForEach(PasteTTL.defaultOptions) { option in
                    Text(option.localizedName)
                        .tag(option)
                }
            } label: {
                FormRow(image: Image(systemName: "timer"), color: SettingsIconColor.clipboard) {
                    Text(viewModel.pasteTTLTitle)
                }
            }
        } header: {
            Text("Clipboard")
        } footer: {
            Text("How long anything you copy from Vault stays on the clipboard.")
        }
    }

    private var universalClipboardSection: some View {
        Section {
            Toggle(isOn: $localSettings.state.allowUniversalClipboardForPasswords) {
                FormRow(image: Image(systemName: "key.fill"), color: SettingsIconColor.universalClipboard) {
                    Text("Passwords")
                }
            }
            Toggle(isOn: $localSettings.state.allowUniversalClipboardForOTPs) {
                FormRow(image: Image(systemName: "number"), color: SettingsIconColor.universalClipboard) {
                    Text("One-time codes")
                }
            }
            Toggle(isOn: $localSettings.state.allowUniversalClipboardForOther) {
                FormRow(image: Image(systemName: "doc.on.clipboard"), color: SettingsIconColor.universalClipboard) {
                    Text("Other")
                }
            }
        } header: {
            Text("Universal Clipboard")
        } footer: {
            Text(
                "When enabled, copied values of the selected kind sync to your other Apple devices via Universal Clipboard. Values are always copied locally; this only controls cross-device sync.",
            )
        }
    }

    private var dangerSection: some View {
        Section {
            Button {
                modal = .danger
            } label: {
                FormRow(image: Image(systemName: "trash.fill"), color: SettingsIconColor.danger) {
                    Text("Delete All Data")
                }
            }
            .tint(.red)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Erase every item and tag from this device.")
        }
    }
}
