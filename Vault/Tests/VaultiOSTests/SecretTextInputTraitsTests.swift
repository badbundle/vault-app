import Foundation
import SwiftUI
import Testing
import UIKit
@testable import VaultiOS

/// What `secretTextInput(_:)` sets up on the UIKit text inputs behind the SwiftUI fields: the traits the keyboard
/// actually reads.
@MainActor
struct SecretTextInputTraitsTests {
    @Test(arguments: [
        (SecretTextInput.prose, UITextAutocapitalizationType.sentences, UIKeyboardType.default),
        (.verbatim, .none, .default),
        (SecretTextInput(capitalization: .characters, isASCIIOnly: true), .allCharacters, .asciiCapable),
    ])
    func labeledTextField_setsUpKeyboardAsDeclared(
        input: SecretTextInput,
        capitalization: UITextAutocapitalizationType,
        keyboard: UIKeyboardType,
    ) throws {
        let field = LabeledTextField("Field", text: .constant(""))
            .secretTextInput(input)

        let traits = try #require(try hostedTextInputTraits(of: field).first)

        #expect(traits.keepsKeyboardFromLearning)
        #expect(traits.autocapitalizationType == capitalization)
        #expect(traits.keyboardType == keyboard)
    }

    @Test
    func labeledTextField_multilineKeepsKeyboardFromLearning() throws {
        let field = LabeledTextField("Field", text: .constant(""), kind: .multiline(minLines: 3))
            .secretTextInput(.prose)

        let traits = try #require(try hostedTextInputTraits(of: field).first)

        #expect(traits.view is UITextView)
        #expect(traits.keepsKeyboardFromLearning)
        #expect(traits.autocapitalizationType == .sentences)
    }

    @Test
    func labeledTextField_secureIsSecureEntryAndKeepsKeyboardFromLearning() throws {
        let field = LabeledTextField("Password", text: .constant(""), kind: .secure())
            .secretTextInput(.verbatim)

        let traits = try hostedTextInputTraits(of: field)

        #expect(traits.contains { $0.isSecureTextEntry })
        #expect(!traits.contains { !$0.keepsKeyboardFromLearning })
    }

    @Test
    func labeledTextField_revealedSecureKeepsKeyboardFromLearning() throws {
        let field = LabeledTextField("Passphrase", text: .constant(""), kind: .secure(isRevealed: .constant(true)))
            .secretTextInput(.verbatim)

        let traits = try hostedTextInputTraits(of: field)

        #expect(!traits.isEmpty)
        #expect(!traits.contains { $0.isSecureTextEntry })
        #expect(!traits.contains { !$0.keepsKeyboardFromLearning })
    }

    @Test
    func labeledTextField_withoutDeclarationIsSetUpVerbatim() throws {
        let field = LabeledTextField("Field", text: .constant(""))

        let traits = try #require(try hostedTextInputTraits(of: field).first)

        #expect(traits.keepsKeyboardFromLearning)
        #expect(traits.autocapitalizationType == .none)
    }

    @Test
    func labeledTextField_declarationWinsOverModifiersAppliedAroundIt() throws {
        let field = LabeledTextField("Field", text: .constant(""))
            .secretTextInput(.prose)
            .autocorrectionDisabled(false)
            .writingToolsBehavior(.complete)
            .textInputAutocapitalization(.characters)
            .keyboardType(.emailAddress)

        let traits = try #require(try hostedTextInputTraits(of: field).first)

        #expect(traits.keepsKeyboardFromLearning)
        #expect(traits.autocapitalizationType == .sentences)
        #expect(traits.keyboardType == .default)
    }

    @Test
    func textField_keepsKeyboardFromLearning() throws {
        let field = TextField("Search", text: .constant(""))
            .secretTextInput(.verbatim)

        let traits = try #require(try hostedTextInputTraits(of: field).first)

        #expect(traits.keepsKeyboardFromLearning)
        #expect(traits.autocapitalizationType == .none)
    }
}

// MARK: - Helpers

extension SecretTextInputTraitsTests {
    struct Traits {
        var view: UIView
        var autocorrectionType: UITextAutocorrectionType
        var autocapitalizationType: UITextAutocapitalizationType
        var keyboardType: UIKeyboardType
        var writingToolsBehavior: UIWritingToolsBehavior
        var isSecureTextEntry: Bool

        /// No autocorrection, which also means no predictive text and nothing learned, and no Writing Tools.
        var keepsKeyboardFromLearning: Bool {
            autocorrectionType == .no && writingToolsBehavior == .none
        }
    }

    /// Hosts `view` in a window and reads the traits of every UIKit text input SwiftUI made for it.
    ///
    /// SwiftUI only makes them once the view is in a window. The test runner has no scene to put one in, so this uses
    /// the window initializer that doesn't take a scene, deprecated as it is.
    @diagnose(DeprecatedDeclaration, as: ignored)
    private func hostedTextInputTraits(of view: some View) throws -> [Traits] {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let controller = UIHostingController(rootView: Form { view })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer {
            window.isHidden = true
        }
        return traits(in: controller.view)
    }

    private func traits(in view: UIView) -> [Traits] {
        let own: Traits? = if let field = view as? UITextField {
            Traits(
                view: field,
                autocorrectionType: field.autocorrectionType,
                autocapitalizationType: field.autocapitalizationType,
                keyboardType: field.keyboardType,
                writingToolsBehavior: field.writingToolsBehavior,
                isSecureTextEntry: field.isSecureTextEntry,
            )
        } else if let textView = view as? UITextView {
            Traits(
                view: textView,
                autocorrectionType: textView.autocorrectionType,
                autocapitalizationType: textView.autocapitalizationType,
                keyboardType: textView.keyboardType,
                writingToolsBehavior: textView.writingToolsBehavior,
                isSecureTextEntry: textView.isSecureTextEntry,
            )
        } else {
            nil
        }
        return (own.map { [$0] } ?? []) + view.subviews.flatMap(traits(in:))
    }
}
