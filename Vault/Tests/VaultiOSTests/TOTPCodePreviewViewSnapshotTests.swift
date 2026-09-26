import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
final class TOTPCodePreviewViewSnapshotTests {
    @Test
    func layout_codeVisible() {
        let sut = makeSUT(state: .visible("123456"))

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_codeError() {
        let error = PresentationError(userTitle: "userTitle", debugDescription: "debugDescription")
        let sut = makeSUT(state: .error(error, digits: 6))

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_codeNotReady() {
        let sut = makeSUT(state: .notReady)

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_noMoreCodes() {
        let sut = makeSUT(state: .finished)

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_obfuscateWithoutMessage() {
        let sut = makeSUT(state: .visible("123456"), behaviour: .editingState(message: nil))

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_obfuscateWithMessage() {
        let sut = makeSUT(state: .visible("123456"), behaviour: .editingState(message: "Custom message"))

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_obfuscateWithLongMessage() {
        let sut = makeSUT(state: .visible("123456"), behaviour: .editingState(message: longMessage()))

        assertSnapshot(of: sut, as: .image)
    }

    @Test(arguments: [6, 7, 8, 20])
    func textWrapping_longCodeMaintainsSameSizeForAllDigits(digits: Int) {
        let code = String(Array(repeating: Character("0"), count: digits))
        let sut = makeSUT(state: .visible(code))

        assertSnapshot(of: sut, as: .image, named: "\(digits)-digits")
    }

    @Test
    func textWrapping_longIssuerStaysOnTwoLines() {
        let sut = makeSUT(issuer: longMessage())

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func textWrapping_longAccountNameStaysOnTwoLines() {
        let sut = makeSUT(accountName: longMessage())

        assertSnapshot(of: sut, as: .image)
    }

    // MARK: - Bar labels

    @Test
    func barLabel_codeExpired() {
        barLabelScenarios(view: makeBarLabelSUT(state: .obfuscated(.expiry)))
    }

    @Test
    func barLabel_codeError() {
        let error = PresentationError(userTitle: "Invalid code", debugDescription: "debugDescription")
        barLabelScenarios(view: makeBarLabelSUT(state: .error(error, digits: 6)))
    }

    /// The countdown's fill ends partway through the label, which changes color where it does.
    @Test
    func barLabel_codeLocked() {
        barLabelScenarios(view: makeBarLabelSUT(state: .locked(code: "123456")))
    }

    @Test
    func barLabel_editing() {
        barLabelScenarios(view: makeBarLabelSUT(behaviour: .editingState(message: "Tap to View")))
    }

    /// Past the largest size the bar grows to, it and its label stay that size.
    @Test
    func barLabel_accessibilitySize() {
        let sut = makeBarLabelSUT(state: .obfuscated(.expiry))
            .dynamicTypeSize(.accessibility3)

        assertSnapshot(of: sut, colorScheme: .light)
    }

    // MARK: - Next code

    /// Near the end of the countdown, the next code shows above the bar without moving anything else on the card.
    @Test(arguments: [ColorScheme.light, .dark])
    func nextCode_showsAboveTheBar(colorScheme: ColorScheme) {
        let sut = makeBarLabelSUT(nextCode: "654321")

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test
    func nextCode_showsAboveTheBarAtALargerTextSize() {
        let sut = makeBarLabelSUT(nextCode: "65432198")
            .dynamicTypeSize(.xxxLarge)

        assertSnapshot(of: sut, colorScheme: .light)
    }

    /// Editing hides the next code along with the current one.
    @Test
    func nextCode_hiddenWhileEditing() {
        let sut = makeBarLabelSUT(nextCode: "654321", behaviour: .editingState(message: "Tap to View"))

        assertSnapshot(of: sut, colorScheme: .light)
    }

    /// With Show Next Code off, the card doesn't show it, even when it's due.
    @Test
    func nextCode_hiddenWithSettingOff() {
        let sut = makeBarLabelSUT(nextCode: "654321", showsNextCode: false)

        assertSnapshot(of: sut, colorScheme: .light)
    }

    // MARK: - Helpers

    /// A card whose timer is a real bar, part way through its countdown, which draws the bar's label.
    ///
    /// - Parameters:
    ///   - nextCode: The next code, as though the countdown is near its end.
    ///   - showsNextCode: The Show Next Code setting.
    private func makeBarLabelSUT(
        state: OTPCodeState = .visible("123456"),
        nextCode: String? = nil,
        showsNextCode: Bool = true,
        behaviour: VaultItemViewBehaviour = .normal,
    ) -> some View {
        let preview = OTPCodePreviewViewModel(
            accountName: "Test",
            issuer: "Issuer",
            color: .default,
            isLocked: false,
            fixedCodeState: state,
            fixedNextCode: nextCode,
        )
        return TOTPCodePreviewView(
            previewViewModel: preview,
            timerView: HorizontalTimerProgressBarView(fractionCompleted: 0.2, color: .blue),
            behaviour: behaviour,
        )
        .environment(\.showsNextCode, showsNextCode)
        .frame(width: 250)
    }

    /// The label in light and dark mode, at the default and a large text size, and with Increase Contrast.
    private func barLabelScenarios(view: some View, testName: String = #function) {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.large, .xxxLarge] {
                assertSnapshot(
                    of: view.dynamicTypeSize(dynamicTypeSize),
                    colorScheme: colorScheme,
                    named: "\(colorScheme)_\(dynamicTypeSize)",
                    testName: testName,
                )
            }
            assertSnapshot(
                of: view,
                colorScheme: colorScheme,
                contrast: .increased,
                named: "\(colorScheme)_increasedContrast",
                testName: testName,
            )
        }
    }

    private func makeSUT(
        accountName: String = "Test",
        issuer: String = "Issuer",
        state: OTPCodeState = .visible("123456"),
        behaviour: VaultItemViewBehaviour = .normal,
    ) -> some View {
        let preview = OTPCodePreviewViewModel(
            accountName: accountName,
            issuer: issuer,
            color: .default,
            isLocked: false,
            fixedCodeState: state,
        )
        return TOTPCodePreviewView(
            previewViewModel: preview,
            timerView: testTimerGradient(),
            behaviour: behaviour,
        )
        .frame(width: 250)
    }

    /// We use this specific gradient for the default timer so it's very clear if it's been overridden.
    private func testTimerGradient() -> some View {
        LinearGradient(colors: [.red, .blue, .green], startPoint: .leading, endPoint: .trailing)
    }

    private func longMessage() -> String {
        """
        This is a very long string which should be long because it is so long \
        This is a very long string which should be long because it is so long \
        This is a very long string which should be long because it is so long
        """
    }
}
