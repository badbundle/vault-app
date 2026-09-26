import Foundation
import SwiftUI

/// How a text field sets up the keyboard, so that nothing typed into Vault is learned by it.
///
/// The system keyboard learns from what's typed so it can autocorrect and predict it later, and what it learns lives
/// outside the vault: it can come back as a suggestion in any app, whether or not Vault is unlocked. Everything typed
/// into Vault is either secret or says something about what the vault holds, so no field lets the keyboard
/// autocorrect, predict or learn, and none offers Writing Tools. What's left to decide for each field is what makes
/// typing easier without learning: how it capitalizes, and whether the keyboard is limited to ASCII.
///
/// Every text input declares one with `secretTextInput(_:)`. A field left to the system's defaults lets the keyboard
/// learn, so `SecretTextInputDeclarationTests` fails for any field that doesn't declare one.
struct SecretTextInput: Equatable {
    enum Capitalization: Equatable {
        case never
        /// The first letter of each sentence.
        case sentences
        /// Every letter.
        case characters
    }

    var capitalization: Capitalization
    /// Limits the keyboard to ASCII characters, for text that can only be ASCII.
    var isASCIIOnly: Bool

    init(capitalization: Capitalization, isASCIIOnly: Bool = false) {
        self.capitalization = capitalization
        self.isASCIIOnly = isASCIIOnly
    }

    /// Written like a sentence: notes, descriptions, titles and names.
    static let prose = SecretTextInput(capitalization: .sentences)

    /// Typed exactly as it has to match: passwords, passphrases, killphrases, account names and searches.
    static let verbatim = SecretTextInput(capitalization: .never)
}

extension View {
    /// Sets up the keyboard for secret text, capitalizing as `input` says: no autocorrection, no predictive text and
    /// nothing learned from what's typed, and no Writing Tools.
    ///
    /// On a `LabeledTextField`, this is what its input is set up with, whatever else is applied around it.
    func secretTextInput(_ input: SecretTextInput) -> some View {
        modifier(SecretTextInputModifier(input: input))
    }
}

private struct SecretTextInputModifier: ViewModifier {
    var input: SecretTextInput

    func body(content: Content) -> some View {
        content
            // With autocorrection off, the keyboard doesn't predict or learn from what's typed either.
            .autocorrectionDisabled()
            .writingToolsBehavior(.disabled)
            .textInputAutocapitalization(input.capitalization.autocapitalization)
            .keyboardType(input.isASCIIOnly ? .asciiCapable : .default)
            .environment(\.secretTextInput, input)
    }
}

extension SecretTextInput.Capitalization {
    fileprivate var autocapitalization: TextInputAutocapitalization {
        switch self {
        case .never: .never
        case .sentences: .sentences
        case .characters: .characters
        }
    }
}

extension EnvironmentValues {
    /// The secret text input declared around a view, which a `LabeledTextField` sets its input up with.
    @Entry var secretTextInput: SecretTextInput?
}
