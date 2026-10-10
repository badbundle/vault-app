import SwiftUI
import VaultFeed
import VaultSettings

/// The Settings window (⌘,): every setting that means something on the Mac, with iOS's defaults (C7). Show in
/// Spotlight isn't here, as Spotlight is always off with the password on (G49), and nor is Turn Off Password (G85).
struct VaultMacSettingsView: View {
    var localSettings: LocalSettings
    var appLock: AppLockService
    var dataModel: VaultDataModel
    var authentication: DeviceAuthenticationService

    /// How wide the window is.
    static let width = 540.0
    /// How tall the General tab is: enough for all its rows at the default text size. At larger sizes it scrolls.
    static let generalHeight = 520.0
    /// How tall the Security tab is, likewise.
    static let securityHeight = 600.0

    /// The window's root, as the Mac's settings window only puts the tabs in its toolbar for a root `TabView`. Each tab
    /// has its own size, which the window takes as the tab is chosen, and shows only that Vault is locked while it is.
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                VaultMacLockedWindowGate {
                    VaultMacGeneralSettings(localSettings: localSettings)
                }
                .frame(width: Self.width, height: Self.generalHeight)
            }
            Tab("Security", systemImage: "lock") {
                VaultMacLockedWindowGate {
                    VaultMacSecuritySettings(
                        localSettings: localSettings,
                        appLock: appLock,
                        dataModel: dataModel,
                        authentication: authentication,
                    )
                }
                .frame(width: Self.width, height: Self.securityHeight)
            }
        }
    }
}

/// Codes, the clipboard and new items.
struct VaultMacGeneralSettings: View {
    @Bindable var localSettings: LocalSettings
    private let titles = SettingsViewModel()

    var body: some View {
        Form {
            Section {
                Picker(titles.codeTapActionTitle, selection: $localSettings.state.codeTapAction) {
                    ForEach(CodeTapAction.allCases) { action in
                        Text(action.localizedName).tag(action)
                    }
                }
                .accessibilityIdentifier("settings.code-tap-action")
                Toggle(titles.showNextCodeTitle, isOn: $localSettings.state.showsNextCode)
                    .accessibilityIdentifier("settings.show-next-code")
            } header: {
                Text("Codes")
            } footer: {
                footnote(
                    "Show Next Code shows what a code will change to in the last seconds of its countdown. Copying still takes the current code.",
                )
            }
            Section {
                Picker(titles.pasteTTLTitle, selection: $localSettings.state.pasteTimeToLive) {
                    ForEach(PasteTTL.defaultOptions) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                .accessibilityIdentifier("settings.clear-clipboard")
                Toggle("Codes Can Reach Other Devices", isOn: $localSettings.state.allowUniversalClipboardForOTPs)
                    .accessibilityIdentifier("settings.universal-clipboard.codes")
                Toggle("Notes Can Reach Other Devices", isOn: $localSettings.state.allowUniversalClipboardForNotes)
                    .accessibilityIdentifier("settings.universal-clipboard.notes")
            } header: {
                Text("Clipboard")
            } footer: {
                footnote(
                    "How long copied codes, notes and details stay on the clipboard, and whether codes and notes can be pasted on your other devices with Universal Clipboard. Descriptions and other details you copy always stay on this Mac.",
                )
            }
            Section {
                Toggle("Lock New Items", isOn: $localSettings.state.lockNewItems)
                    .accessibilityIdentifier("settings.lock-new-items")
            } header: {
                Text("New Items")
            } footer: {
                footnote("New codes and notes start locked, so they need Touch ID or your Mac's password to see.")
            }
        }
        .formStyle(.grouped)
    }
}

/// The lock, the App Lock Password, Hide While Recording and Delete All Data.
struct VaultMacSecuritySettings: View {
    @Bindable var localSettings: LocalSettings
    var appLock: AppLockService
    var dataModel: VaultDataModel
    var authentication: DeviceAuthenticationService

    /// Where the user has just moved the delay, held there while they authenticate.
    @State private var requestedDelay: AppLockDelay?
    @State private var passwordForm: PasswordFormRequest?
    @State private var isShowingDeleteAllData = false

    private struct PasswordFormRequest: Identifiable {
        let id = UUID()
        var purpose: AppLockPasswordFormViewModel.Purpose
    }

    var body: some View {
        Form {
            Section {
                Picker("Require Unlock", selection: Binding(
                    get: { requestedDelay ?? appLock.delay },
                    set: { newValue in
                        requestedDelay = newValue
                        Task {
                            await appLock.setDelay(newValue)
                            requestedDelay = nil
                        }
                    },
                )) {
                    ForEach(AppLockDelay.allCases) { delay in
                        Text(delay.localizedName).tag(delay)
                    }
                }
                .disabled(appLock.isChangingSettings)
                .accessibilityIdentifier("settings.require-unlock")
                Toggle("Hide While Recording", isOn: $localSettings.state.hidesVaultWhileScreenCaptured)
                    .accessibilityIdentifier("settings.hide-while-recording")
            } header: {
                Text("Security")
            } footer: {
                footnote(
                    "How long Vault can be behind other apps before it locks. It always locks at once when the screen locks or the Mac sleeps. Hide While Recording keeps Vault's windows out of screenshots, screen recordings and screen sharing.",
                )
            }
            Section {
                LabeledContent("App Lock Password", value: "On")
                Button("Change Password…") { passwordForm = .init(purpose: .change) }
                    .accessibilityIdentifier("settings.password.change")
                Button("Set Duress Password…") { passwordForm = .init(purpose: .setDuress) }
                    .accessibilityIdentifier("settings.password.duress")
                LabeledContent(
                    "Erase Vault After \(AppLockPasswordAttemptCounter.eraseThreshold) Failed Passwords",
                ) {
                    HStack {
                        Text(appLock.erasesAfterFailedPasswords ? "On" : "Off")
                            .foregroundStyle(.secondary)
                        Button(appLock.erasesAfterFailedPasswords ? "Turn Off…" : "Turn On…") {
                            passwordForm = .init(purpose: appLock.erasesAfterFailedPasswords
                                ? .turnOffErasing
                                : .turnOnErasing)
                        }
                        .accessibilityIdentifier("settings.password.erasing")
                    }
                }
            } header: {
                Text("App Lock Password")
            } footer: {
                footnote(
                    "Vault on the Mac always has an App Lock Password. Changing it, setting a duress password or erasing after failed passwords needs the current one.",
                )
            }
            Section {
                Button("Delete All Data…", role: .destructive) {
                    isShowingDeleteAllData = true
                }
                .accessibilityIdentifier("settings.delete-all-data")
            } header: {
                Text("Danger Zone")
            } footer: {
                footnote(
                    "Deletes every vault on this Mac, and the open vault's backup password. Backups you've saved aren't deleted.",
                )
            }
        }
        .formStyle(.grouped)
        .sheet(item: $passwordForm) { request in
            VaultMacAppLockPasswordForm(
                viewModel: AppLockPasswordFormViewModel(purpose: request.purpose, appLock: appLock),
                close: { passwordForm = nil },
            )
        }
        .sheet(isPresented: $isShowingDeleteAllData) {
            VaultMacDeleteAllDataSheet(
                viewModel: SettingsDangerViewModel(dataModel: dataModel, authenticationService: authentication),
                close: { isShowingDeleteAllData = false },
            )
        }
    }
}

/// Delete All Data: what it deletes and keeps, then "Delete everything?", then Touch ID or the Mac's password, as on
/// iOS (G15, G31).
struct VaultMacDeleteAllDataSheet: View {
    @State var viewModel: SettingsDangerViewModel
    var close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(viewModel.state == .deleted ? "Everything Was Deleted" : "Delete All Data?")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .accessibilityIdentifier("settings.delete-all-data.message")
            HStack {
                if viewModel.state == .deleted {
                    Button("Done", action: close)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) {
                        viewModel.cancelConfirmation()
                        close()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isDeleting)
                    if viewModel.isShowingConfirmation {
                        Button("Delete Everything", role: .destructive) {
                            Task { await viewModel.deleteEntireVault() }
                        }
                        .disabled(viewModel.isDeleting)
                        .accessibilityIdentifier("settings.delete-all-data.confirm")
                    } else {
                        Button("Continue…", role: .destructive) {
                            viewModel.askToConfirm()
                        }
                        .disabled(viewModel.needsPasscode)
                        .accessibilityIdentifier("settings.delete-all-data.continue")
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    private var message: String {
        switch viewModel.state {
        case .overview:
            viewModel.needsPasscode
                ? "Deleting all data needs Touch ID or your Mac's login password. Set one up first."
                : "Every item and tag in every vault on this Mac is deleted, with the open vault's backup password. It can't be undone. Backups you've saved stay where they are."
        case .confirming:
            "Delete everything? You'll be asked for Touch ID or your Mac's password."
        case .deleting:
            "Deleting…"
        case let .failed(error):
            error.userDescription ?? error.userTitle
        case .deleted:
            "Vault is empty. Restore a backup to bring your items back."
        }
    }
}

extension VaultMacGeneralSettings {
    fileprivate func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

extension VaultMacSecuritySettings {
    fileprivate func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
