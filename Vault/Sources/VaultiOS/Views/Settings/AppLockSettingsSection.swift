import Foundation
import SwiftUI
import VaultFeed

/// The Security section of Settings: the app lock, which takes authenticating to turn on or off, and, while it's on,
/// how soon it locks and the App Lock Password.
///
/// The password is only offered once its storage is in (`AppLockService.offersPassword`). While it's set, the lock
/// can't be turned off: the password has to be turned off first, which needs the password.
struct AppLockSettingsSection: View {
    @Environment(AppLockService.self) private var appLock
    /// Where the user has just moved the toggle, held there while they authenticate.
    @State private var requestedIsEnabled: Bool?
    /// Likewise for the delay.
    @State private var requestedDelay: AppLockDelay?
    /// The App Lock Password's sheet, and whether the password was set when it opened.
    @State private var passwordSheet: PasswordSheet?

    private struct PasswordSheet: Identifiable {
        var startsWithPasswordSet: Bool

        var id: Bool {
            startsWithPasswordSet
        }
    }

    var body: some View {
        Section {
            Toggle(isOn: isEnabled) {
                FormRow(image: Image(systemName: "lock.fill"), color: SettingsIconColor.security) {
                    Text("App Lock")
                }
            }
            .disabled(!appLock.canEnable || !appLock.canDisable || isChanging)

            if appLock.isEnabled {
                Picker(selection: delay) {
                    ForEach(AppLockDelay.allCases) { option in
                        Text(option.localizedName)
                            .tag(option)
                    }
                } label: {
                    FormRow(image: Image(systemName: "hourglass"), color: SettingsIconColor.security) {
                        Text("Require Unlock")
                    }
                }
                .disabled(isChanging)

                if appLock.offersPassword {
                    passwordRow
                }
            }
        } header: {
            Text("Security")
        } footer: {
            Text(footer)
        }
        .animation(.snappy, value: appLock.isEnabled)
    }

    private var passwordRow: some View {
        Button {
            passwordSheet = PasswordSheet(startsWithPasswordSet: appLock.isPasswordSet)
        } label: {
            SheetRowLabel(
                title: "App Lock Password",
                value: appLock.isPasswordSet ? "On" : "Off",
                systemImage: "ellipsis.rectangle.fill",
                color: SettingsIconColor.security,
            )
        }
        .disabled(isChanging)
        // What the sheet shows is fixed when it opens, so setting the password shows that it's set, rather than
        // swapping to the screen for a password that's on.
        .sheet(item: $passwordSheet) { sheet in
            AppLockPasswordSheet(startsWithPasswordSet: sheet.startsWithPasswordSet)
        }
    }

    private var isChanging: Bool {
        requestedIsEnabled != nil || requestedDelay != nil
    }

    private var isEnabled: Binding<Bool> {
        Binding {
            requestedIsEnabled ?? appLock.isEnabled
        } set: { newValue in
            requestedIsEnabled = newValue
            Task {
                await appLock.setEnabled(newValue)
                requestedIsEnabled = nil
            }
        }
    }

    private var delay: Binding<AppLockDelay> {
        Binding {
            requestedDelay ?? appLock.delay
        } set: { newValue in
            requestedDelay = newValue
            Task {
                await appLock.setDelay(newValue)
                requestedDelay = nil
            }
        }
    }

    private var footer: String {
        if !appLock.canDisable {
            "Ask for Face ID, Touch ID or your passcode, then the App Lock Password, to open Vault. To turn off App Lock, turn off the App Lock Password first."
        } else if appLock.canEnable {
            "Ask for Face ID, Touch ID or your passcode to open Vault. While it's on, widgets hide your codes and AutoFill asks first."
        } else {
            "Set up a passcode on this device to use App Lock."
        }
    }
}
