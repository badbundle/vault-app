import SwiftUI
import VaultFeed
import VaultiOSShared

/// The current code on an OTP card in the feed, drawn the same way for every
/// code type.
///
/// Only the card's width decides how large the code is: it scales down to fit
/// across the card, but always takes its full height. Were it allowed to give
/// up height, it would be the line that shrinks whenever a card runs short of
/// room (an issuer on two lines, a narrow phone, a larger text size), and an
/// HOTP card, whose refresh button makes its bottom row taller, would draw a
/// smaller code than a TOTP card beside it.
struct OTPPreviewCodeText: View {
    var codeState: OTPCodeState
    var behaviour: VaultItemViewBehaviour

    var body: some View {
        OTPCodeTextView(codeState: isEditing ? .notReady : codeState)
            .font(.system(.largeTitle, design: .monospaced))
            .fontWeight(.heavy)
            .lineLimit(1)
            .foregroundStyle(isEditing ? .white : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isEditing: Bool {
        switch behaviour {
        case .normal: false
        case .editingState: true
        }
    }
}
