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
    @ScaledMetric(relativeTo: .title3) private var iconSize: Double = 44

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
            }
        }
        .padding(.horizontal, 20)
        // Room above the title for the drag indicator.
        .padding(.top, 28)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The sheet hugs the content rather than snapping to `.medium`,
        // which would leave half the sheet empty below two rows. Measured
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
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
    ) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.accentColor, in: .rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                // The sheet's height comes from measuring this content, so
                // the first pass lays it out in a zero-height sheet and the
                // text would truncate to one line, which then becomes the
                // measured height. Sizing the text to its own height breaks
                // the loop and lets the subtitle wrap.
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 20))
            // The whole row is the target, not just the text.
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
