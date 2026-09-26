import Foundation
import SwiftUI
import VaultFeed

/// The Security section of Settings: the app lock, which takes authenticating to turn on or off, and, while it's on,
/// how soon it locks.
struct AppLockSettingsSection: View {
    @Environment(AppLockService.self) private var appLock
    /// Where the user has just moved the toggle, held there while they authenticate.
    @State private var requestedIsEnabled: Bool?
    /// Likewise for the delay.
    @State private var requestedDelay: AppLockDelay?

    var body: some View {
        Section {
            Toggle(isOn: isEnabled) {
                FormRow(image: Image(systemName: "lock.fill"), color: SettingsIconColor.security) {
                    Text("App Lock")
                }
            }
            .disabled(!appLock.canEnable || isChanging)

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
            }
        } header: {
            Text("Security")
        } footer: {
            Text(footer)
        }
        .animation(.snappy, value: appLock.isEnabled)
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
        if appLock.canEnable {
            "Ask for Face ID, Touch ID or your passcode to open Vault. While it's on, widgets hide your codes and AutoFill asks first."
        } else {
            "Set up a passcode on this device to use App Lock."
        }
    }
}
