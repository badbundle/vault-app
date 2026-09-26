import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
final class HOTPCodePreviewViewSnapshotTests {
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

    @Test
    func textWrapping_longCodeMaintainsSameSizeForAllDigits() {
        let digits = [6, 7, 8, 20]
        for count in digits {
            let code = String(Array(repeating: Character("0"), count: count))
            let sut = makeSUT(state: .visible(code))

            assertSnapshot(of: sut, as: .image, named: "\(count)-digits")
        }
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
        barLabelScenarios(view: makeSUT(state: .obfuscated(.expiry)))
    }

    @Test
    func barLabel_codeError() {
        let error = PresentationError(userTitle: "Invalid code", debugDescription: "debugDescription")
        barLabelScenarios(view: makeSUT(state: .error(error, digits: 6)))
    }

    @Test
    func barLabel_codeLocked() {
        barLabelScenarios(view: makeSUT(state: .locked(code: "123456")))
    }

    @Test
    func barLabel_editing() {
        barLabelScenarios(view: makeSUT(behaviour: .editingState(message: "Tap to View")))
    }

    /// Past the largest size the bar grows to, it and its label stay that size.
    @Test
    func barLabel_accessibilitySize() {
        let sut = makeSUT(state: .obfuscated(.expiry))
            .dynamicTypeSize(.accessibility3)

        assertSnapshot(of: sut, colorScheme: .light)
    }

    // MARK: - Helpers

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
        return HOTPCodePreviewView(
            buttonView: OTPCodeButtonIcon(isError: false),
            previewViewModel: preview,
            behaviour: behaviour,
        )
        .frame(width: 250)
    }

    private func longMessage() -> String {
        """
        This is a very long string which should be long because it is so long \
        This is a very long string which should be long because it is so long \
        This is a very long string which should be long because it is so long
        """
    }
}
