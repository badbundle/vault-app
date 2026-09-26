import Foundation
import SwiftUI
import VaultSettings

/// How codes in the vault behave: what tapping one does, and whether a time-based code shows the next one as it's
/// about to change.
struct CodesSettingsSection: View {
    var viewModel: SettingsViewModel
    @Bindable var localSettings: LocalSettings

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
        } header: {
            Text("Codes")
        } footer: {
            Text(
                "Whichever you choose, touch and hold a code to copy it or see its details. Show Next Code shows what a code will change to in the last seconds of its countdown. Copying still takes the current code.",
            )
        }
    }
}
