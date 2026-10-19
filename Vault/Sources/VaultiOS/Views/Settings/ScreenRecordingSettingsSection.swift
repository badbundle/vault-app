import Foundation
import SwiftUI
import VaultSettings

/// Whether the vault hides while the screen is recorded, mirrored or shared. Independent of the app lock.
struct ScreenRecordingSettingsSection: View {
    @Bindable var localSettings: LocalSettings

    var body: some View {
        Section {
            Toggle(isOn: $localSettings.state.hidesVaultWhileScreenCaptured) {
                FormRow(image: Image(systemName: "record.circle"), color: SettingsIconColor.screenRecording) {
                    Text("Hide While Recording")
                }
            }
        } header: {
            Text("Screen Recording")
        } footer: {
            Text(
                "Cover Vault while your screen is recorded, mirrored or shared, so your items don't show. Recovery phrases and private keys always hide, whatever this says.",
            )
        }
    }
}
