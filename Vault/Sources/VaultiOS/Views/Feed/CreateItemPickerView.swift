import Foundation
import SwiftUI

/// Bottom sheet that asks which kind of item to create.
///
/// This used to be a toolbar `Menu`, but a menu packs its rows tightly
/// under the button and gives no room to explain the choice, so it was
/// easy to mis-tap. A sheet gives each option a full-width row with a
/// description, sized to its content so it only takes the space it needs.
@MainActor
struct CreateItemPickerView: View {
    var onSelect: (CreatingItem) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Item")
                .font(.title2.bold())

            VStack(spacing: 12) {
                option(
                    .otpCode,
                    title: "Code",
                    subtitle: "2FA timer or counter based codes",
                    systemImage: "qrcode",
                )
                option(
                    .secureNote,
                    title: "Note",
                    subtitle: "Freeform text",
                    systemImage: "text.alignleft",
                )
                option(
                    .recoveryPhrase,
                    title: "Recovery Phrase",
                    subtitle: "Crypto wallet seed words",
                    systemImage: "list.number",
                )
            }
        }
        .padding(.horizontal, 20)
        // Room above the title for the drag indicator.
        .padding(.top, 28)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The sheet hugs the content rather than snapping to `.medium`,
        // which would leave half the sheet empty below the rows. Measured
        // rather than fixed so Dynamic Type sizes still fit.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newValue in
            contentHeight = newValue
        }
        // Until the first measurement lands a zero-height detent is invalid
        // (UIKit logs and ignores it), so fall back to `.medium` for that pass.
        .presentationDetents([contentHeight > 0 ? .height(contentHeight) : .medium])
        // Detents only apply to phone-style sheets; this keeps the iPad
        // form sheet from opening as a tall, mostly empty panel.
        .presentationSizing(.fitted)
        .presentationDragIndicator(.visible)
    }

    private func option(
        _ item: CreatingItem,
        title: String,
        subtitle: String,
        systemImage: String,
    ) -> some View {
        Button {
            onSelect(item)
        } label: {
            OptionCardLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                .padding(16)
                .background(.fill.quaternary, in: .rect(cornerRadius: 20))
                .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var isPresented = true

    Color.clear
        .sheet(isPresented: $isPresented) {
            CreateItemPickerView { _ in
                isPresented = false
            }
        }
}
