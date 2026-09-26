import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

/// An HOTP card beside a TOTP card at the size the feed draws them, so any
/// difference in how large each draws its code shows side by side.
///
/// Whatever else is in the card, an issuer on two lines or the HOTP card's
/// refresh button, the code should be the same size in both.
@MainActor
struct OTPCodePreviewCodeSizeSnapshotTests {
    @Test(arguments: [6, 7, 8])
    func codeMatchesAcrossTypes(digits: Int) {
        let sut = makeSUT(code: String(repeating: "0", count: digits))

        assertSnapshot(of: sut, as: .image, named: "\(digits)-digits")
    }

    @Test
    func codeMatchesAcrossTypes_withIssuerOnTwoLines() {
        let sut = makeSUT(issuer: "Legacy VPN Gateway")

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func codeMatchesAcrossTypes_atLargerTextSize() {
        let sut = makeSUT()
            .dynamicTypeSize(.xxLarge)

        assertSnapshot(of: sut, as: .image)
    }

    /// The tightest case: a narrower card with the issuer on two lines leaves
    /// the least room, which is where the HOTP code used to shrink.
    @Test(arguments: [6, 7, 8])
    func codeMatchesAcrossTypes_onNarrowerPhoneWithIssuerOnTwoLines(digits: Int) {
        let sut = makeSUT(
            issuer: "Legacy VPN Gateway",
            code: String(repeating: "0", count: digits),
            cardWidth: 175,
        )

        assertSnapshot(of: sut, as: .image, named: "\(digits)-digits")
    }

    // MARK: - Helpers

    /// - Parameter cardWidth: One column of the feed's two-column grid: 198pt
    ///   on a 440pt-wide phone, 175pt on a 390pt one.
    private func makeSUT(
        issuer: String = "Issuer",
        code: String = "123456",
        cardWidth: CGFloat = 198,
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HOTPCodePreviewView(
                buttonView: OTPCodeButtonIcon(isError: false),
                previewViewModel: makePreviewViewModel(issuer: issuer, code: code),
                behaviour: .normal,
            )
            .frame(width: cardWidth)

            TOTPCodePreviewView(
                previewViewModel: makePreviewViewModel(issuer: issuer, code: code),
                timerView: Color.blue,
                behaviour: .normal,
            )
            .frame(width: cardWidth)
        }
        .padding(8)
    }

    private func makePreviewViewModel(issuer: String, code: String) -> OTPCodePreviewViewModel {
        OTPCodePreviewViewModel(
            accountName: "bradley@example.com",
            issuer: issuer,
            color: .default,
            isLocked: false,
            fixedCodeState: .visible(code),
        )
    }
}
