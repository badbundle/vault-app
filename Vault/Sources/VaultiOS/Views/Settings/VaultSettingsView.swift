import SwiftUI
import VaultCore
import VaultFeed
import VaultSettings

/// The app's settings, one section per group.
///
/// Every section has a heading and a short footer, so each reads as a card of its own. Rows are
/// single-line `FormRow`s with a prominent icon in their section's `SettingsIconColor`, so they're all the same
/// height whether they hold a toggle, a picker or a button. A group of related options too big for a row opens a
/// fitted sheet from a row that summarizes it. The Danger Zone stays last.
@MainActor
struct VaultSettingsView: View {
    @Environment(VaultDataModel.self) private var dataModel
    @Environment(DeviceAuthenticationService.self) private var authenticationService
    @State private var viewModel: SettingsViewModel
    @Bindable private var localSettings: LocalSettings

    @State private var modal: Modal?

    private enum Modal: IdentifiableSelf {
        case universalClipboard
        case danger
    }

    init(viewModel: SettingsViewModel, localSettings: LocalSettings) {
        _viewModel = State(wrappedValue: viewModel)
        _localSettings = Bindable(wrappedValue: localSettings)
    }

    var body: some View {
        Form {
            AppLockSettingsSection()
            ScreenRecordingSettingsSection(localSettings: localSettings)
            CodesSettingsSection(viewModel: viewModel, localSettings: localSettings)
            NewItemsSettingsSection(localSettings: localSettings)
            clipboardSection
            dangerSection
        }
        // A little more room than the default between sections, so a footer doesn't run into the next heading.
        .listSectionSpacing(.custom(28))
        .navigationTitle(viewModel.title)
        .sheet(item: $modal, onDismiss: nil) { item in
            switch item {
            case .universalClipboard:
                UniversalClipboardSheet(localSettings: localSettings)
            case .danger:
                SettingsDangerView(viewModel: .init(
                    dataModel: dataModel,
                    authenticationService: authenticationService,
                ))
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

            Button {
                modal = .universalClipboard
            } label: {
                SheetRowLabel(
                    title: "Universal Clipboard",
                    value: universalClipboardSummary,
                    systemImage: "iphone.and.arrow.right.outward",
                    color: SettingsIconColor.clipboard,
                )
            }
        } header: {
            Text("Clipboard")
        } footer: {
            Text(
                "How long copied codes, notes and details stay on the clipboard, and whether they can reach your other devices.",
            )
        }
    }

    private var universalClipboardSummary: String {
        switch localSettings.state.universalClipboardSummary {
        case .off: "Off"
        case .on: "On"
        case let .only(contentTypes): contentTypes.map(\.universalClipboardName).formatted(.list(type: .and)) + " Only"
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

extension PasteboardContentType {
    /// How the Universal Clipboard row names this kind of value when it's the only one on.
    fileprivate var universalClipboardName: String {
        switch self {
        case .otp: "Codes"
        case .note: "Notes"
        case .detail: "Details"
        }
    }
}

/// The label of a Settings row that opens a sheet: the setting's name, a summary of its value and a chevron, so it
/// reads like the rows around it rather than as a tinted button.
struct SheetRowLabel: View {
    var title: String
    var value: String
    var systemImage: String
    var color: Color

    var body: some View {
        FormRow(image: Image(systemName: systemImage), color: color) {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(value)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .accessibilityHidden(true)
                }
            } label: {
                // Explicit, so the button doesn't tint it.
                Text(title)
                    .foregroundStyle(Color(uiColor: .label))
            }
        }
    }
}
