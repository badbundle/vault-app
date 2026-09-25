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
}
