import Foundation
import SwiftUI

/// A switch laid out like `OptionCardLabel`: an icon on an accent square, a title with a subtitle beneath, and the
/// switch where the chevron would be.
///
/// For a setting on a sheet whose other choices are cards. Like `OptionCardLabel`, it draws no background: the
/// container gives it its card.
struct OptionCardToggle: View {
    var title: String
    var subtitle: String
    var systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                OptionCardIcon(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .multilineTextAlignment(.leading)
                // A sheet that measures this to size itself would otherwise lay it out in a zero-height sheet first,
                // and truncate the text to one line. Sizing the text to its own height lets the subtitle wrap.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    @Previewable @State var isOn = false

    OptionCardToggle(
        title: "One-Time Codes",
        subtitle: isOn ? "Codes you copy can be pasted on your other devices." : "Codes you copy stay on this device.",
        systemImage: "qrcode",
        isOn: $isOn.animation(),
    )
    .padding(16)
    .background(.fill.quaternary, in: .rect(cornerRadius: 20))
    .padding()
}
