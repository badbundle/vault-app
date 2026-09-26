import Foundation
import Testing
import VaultFeed
@testable import VaultiOS

struct LabeledTextFieldStatusTests {
    @Test
    func initErrorFrom_validIsNotFlagged() {
        #expect(LabeledTextField.Status(errorFrom: .valid) == .none)
    }

    @Test
    func initErrorFrom_unfinishedIsNotFlagged() {
        #expect(LabeledTextField.Status(errorFrom: .invalid) == .none)
    }

    @Test
    func initErrorFrom_errorKeepsItsMessage() {
        #expect(LabeledTextField.Status(errorFrom: .error(message: "Bad")) == .error(message: "Bad"))
        #expect(LabeledTextField.Status(errorFrom: .error()) == .error())
    }

    @Test
    func passwordConfirmation_describesWhetherPasswordsMatch() {
        #expect(
            LabeledTextField.Status.passwordConfirmation(matches: true)
                == .valid(accessibilityDescription: "Passwords match"),
        )
        #expect(
            LabeledTextField.Status.passwordConfirmation(matches: false)
                == .error(accessibilityDescription: "Passwords don't match"),
        )
    }

    @Test
    func iconAccessibilityLabel_noneHasNoIcon() {
        #expect(LabeledTextField.Status.none.iconAccessibilityLabel == nil)
    }

    @Test
    func iconAccessibilityLabel_validUsesDescriptionFallingBackToValid() {
        #expect(LabeledTextField.Status.valid().iconAccessibilityLabel == "Valid")
        #expect(
            LabeledTextField.Status.valid(accessibilityDescription: "Passwords match").iconAccessibilityLabel
                == "Passwords match",
        )
    }

    @Test
    func iconAccessibilityLabel_errorUsesDescriptionFallingBackToInvalid() {
        #expect(LabeledTextField.Status.error().iconAccessibilityLabel == "Invalid")
        #expect(
            LabeledTextField.Status.error(accessibilityDescription: "Passwords don't match").iconAccessibilityLabel
                == "Passwords don't match",
        )
    }

    @Test
    func iconAccessibilityLabel_errorWithMessageLeavesTheMessageToBeRead() {
        #expect(LabeledTextField.Status.error(message: "Too short").iconAccessibilityLabel == nil)
        #expect(
            LabeledTextField.Status.error(message: "Too short", accessibilityDescription: "Invalid key")
                .iconAccessibilityLabel == "Invalid key",
        )
    }
}
