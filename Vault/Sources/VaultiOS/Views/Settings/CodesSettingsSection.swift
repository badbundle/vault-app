import Foundation
import SwiftUI
import VaultFeed
import VaultSettings

/// How codes in the vault behave: what tapping one does, whether a time-based code shows the next one as it's about
/// to change, and whether their names can be found in Spotlight.
struct CodesSettingsSection: View {
    var viewModel: SettingsViewModel
    @Bindable var localSettings: LocalSettings
    @Environment(AppLockService.self) private var appLock

    var body: some View {
        Section {
            Picker(selection: $localSettings.state.codeTapAction) {
                ForEach(CodeTapAction.allCases) { option in
                    Text(option.localizedName)
                        .tag(option)
                }
            } label: {
                FormRow(image: Image(systemName: "hand.tap.fill"), color: SettingsIconColor.codes) {
                    Text(viewModel.codeTapActionTitle)
                }
            }
            Toggle(isOn: $localSettings.state.showsNextCode) {
                FormRow(image: Image(systemName: "hourglass.bottomhalf.filled"), color: SettingsIconColor.codes) {
                    Text(viewModel.showNextCodeTitle)
                }
            }
            Toggle(isOn: showsCodesInSpotlight) {
                FormRow(image: Image(systemName: "magnifyingglass"), color: SettingsIconColor.codes) {
                    Text("Show in Spotlight")
                }
            }
            .disabled(isAppLockOn)
        } header: {
            Text("Codes")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Whichever you choose, touch and hold a code to copy it or see its details. Show Next Code shows what a code will change to in the last seconds of its countdown. Copying still takes the current code.",
                )
                Text(spotlightFooter)
            }
        }
    }

    /// Spotlight can be searched without opening Vault, so it's never shown anything while App Lock is on (VAULT-72).
    private var isAppLockOn: Bool {
        appLock.isEnabled || appLock.isPasswordSet
    }

    /// Off while App Lock is on. Turning App Lock on turns it off anyway (`VaultRoot`), but this shows it off straight
    /// away.
    private var showsCodesInSpotlight: Binding<Bool> {
        Binding {
            localSettings.state.showsCodesInSpotlight && !isAppLockOn
        } set: { isOn in
            localSettings.state.showsCodesInSpotlight = isOn
        }
    }

    private var spotlightFooter: String {
        if isAppLockOn {
            "Show in Spotlight can't be on while App Lock is, because Spotlight shows codes without Vault being unlocked."
        } else {
            "Show in Spotlight lets you find a code by its site's name in Spotlight and Apple Intelligence, without opening Vault. Account names never show, nor do locked or hidden codes. Turning on App Lock turns it off."
        }
    }
}
