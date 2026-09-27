import Foundation
import SwiftUI
import VaultFeed

/// The App Lock Password's settings, in a sheet from the Security section: setting it up where there's none, or
/// changing it or turning it off.
///
/// Every flow ends back in Settings, which shows the password on or off.
struct AppLockPasswordSheet: View {
    /// Whether the password was set when the sheet opened, which decides what it shows for as long as it's open.
    var startsWithPasswordSet: Bool

    @Environment(AppLockService.self) private var appLock
    @Environment(VaultDataModel.self) private var dataModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if startsWithPasswordSet {
                AppLockPasswordManageView(close: close)
            } else {
                AppLockPasswordFormView(
                    viewModel: AppLockPasswordFormViewModel(purpose: .set, appLock: appLock),
                    lastBackup: dataModel.lastBackupEvent,
                    close: close,
                )
            }
        }
    }

    private func close() {
        dismiss()
    }
}

/// The App Lock Password while it's set: what it does, the ways to change it or turn it off, setting a duress
/// password, and erasing after too many wrong ones.
///
/// It looks the same whether or not a duress password was set, and in a duress vault as in the real one. There's no
/// way to see, change or remove a duress password, only to set one again (MANIFESTO.md C2, C5, C9). Erasing is a
/// setting of the device, so it shows the same in every vault too.
struct AppLockPasswordManageView: View {
    var close: () -> Void

    @Environment(AppLockService.self) private var appLock
    @Environment(VaultDataModel.self) private var dataModel

    var body: some View {
        Form {
            Section {
                BackupHeroHeader(
                    title: "App Lock Password",
                    subtitle: "Vault asks for it every time it unlocks, after Face ID, Touch ID or your passcode. It's a different password from your backup password.",
                    systemImage: "ellipsis.rectangle.fill",
                    color: .accentColor,
                    iconSize: 56,
                ) {
                    statusLabel
                }
            }

            Section {
                NavigationLink {
                    AppLockPasswordFormView(
                        viewModel: AppLockPasswordFormViewModel(purpose: .change, appLock: appLock),
                        close: close,
                    )
                } label: {
                    FormRow(image: Image(systemName: "key.fill"), color: SettingsIconColor.security) {
                        Text("Change Password")
                    }
                }

                NavigationLink {
                    AppLockPasswordFormView(
                        viewModel: AppLockPasswordFormViewModel(purpose: .turnOff, appLock: appLock),
                        close: close,
                    )
                } label: {
                    FormRow(image: Image(systemName: "lock.open.fill"), color: SettingsIconColor.danger) {
                        Text("Turn Off Password")
                    }
                }

                NavigationLink {
                    AppLockPasswordFormView(
                        viewModel: AppLockPasswordFormViewModel(purpose: .setDuress, appLock: appLock),
                        close: close,
                    )
                } label: {
                    FormRow(
                        image: Image(systemName: AppLockPasswordFormView.duressSystemImage),
                        color: SettingsIconColor.security,
                    ) {
                        Text("Set Duress Password")
                    }
                }
            } footer: {
                Text("Changing the password or turning it off needs the current one.")
            }

            eraseSection
        }
        .navigationTitle("App Lock Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: close)
            }
        }
    }

    /// Erasing every vault after too many wrong passwords in a row. Turning it on or off needs the current password,
    /// like changing the password does, so the row opens that form rather than being a switch.
    private var eraseSection: some View {
        Section {
            NavigationLink {
                AppLockPasswordFormView(
                    viewModel: AppLockPasswordFormViewModel(
                        purpose: appLock.erasesAfterFailedPasswords ? .turnOffErasing : .turnOnErasing,
                        appLock: appLock,
                    ),
                    lastBackup: dataModel.lastBackupEvent,
                    close: close,
                )
            } label: {
                FormRow(image: Image(systemName: "trash.fill"), color: SettingsIconColor.danger) {
                    // The value stays on the trailing edge while the long title wraps, as in Settings.
                    HStack {
                        Text("Erase Vault After \(AppLockPasswordAttemptCounter.eraseThreshold) Failed Passwords")
                        Spacer(minLength: 8)
                        Text(appLock.erasesAfterFailedPasswords ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } footer: {
            Text(
                "When it's on, \(AppLockPasswordAttemptCounter.eraseThreshold) wrong App Lock Passwords in a row erase every vault on this iPhone, including any duress vault. The only way back is a backup.",
            )
        }
    }

    /// Makes it clear the password is on, like the backup password's screen does.
    private var statusLabel: some View {
        // Not a `Label`: inside a form row, its icon takes the row's icon column width.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("On")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.fill.tertiary, in: .capsule)
    }
}
