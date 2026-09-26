import Foundation
import SwiftUI
import VaultSettings

/// What tapping a code in the vault does.
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
        } header: {
            Text("Codes")
        } footer: {
            Text("Whichever you choose, touch and hold a code to copy it or see its details.")
        }
    }
}
