import Foundation
import SwiftUI
import VaultSettings

/// Bottom sheet for choosing which copied values can reach the user's other devices over Universal Clipboard.
///
/// Laid out like the New Item picker: a title, a short explanation, then a card for each kind of value Vault copies.
/// Each is off until the user turns it on (MANIFESTO C7), and a new kind of value gets a card of its own here.
@MainActor
struct UniversalClipboardSheet: View {
    @Bindable var localSettings: LocalSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(
                title: "Universal Clipboard",
                message: "Copy on this device, then paste on your other Apple devices nearby. Turn it on only for what you need there.",
            )

            VStack(spacing: 12) {
                OptionCardToggle(
                    title: "One-Time Codes",
                    subtitle: localSettings.state.allowUniversalClipboardForOTPs
                        ? "Codes you copy can be pasted on your other devices."
                        : "Codes you copy stay on this device.",
                    systemImage: "qrcode",
                    isOn: $localSettings.state.allowUniversalClipboardForOTPs.animation(),
                )
                .optionCardBackground()

                OptionCardToggle(
                    title: "Notes",
                    subtitle: localSettings.state.allowUniversalClipboardForNotes
                        ? "Text you copy from notes can be pasted on your other devices."
                        : "Text you copy from notes stays on this device.",
                    systemImage: "text.alignleft",
                    isOn: $localSettings.state.allowUniversalClipboardForNotes.animation(),
                )
                .optionCardBackground()
            }

            Text("Descriptions and other details you copy always stay on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                // Wraps rather than truncating while the sheet measures itself.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        // Room above the title for the drag indicator.
        .padding(.top, 28)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fittedSheet()
    }
}

#Preview {
    @Previewable @State var isPresented = true
    @Previewable @State var localSettings = LocalSettings(defaults: .init(userDefaults: .standard))

    Color.clear
        .sheet(isPresented: $isPresented) {
            UniversalClipboardSheet(localSettings: localSettings)
        }
}
