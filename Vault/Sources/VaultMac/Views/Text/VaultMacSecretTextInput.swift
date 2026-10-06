import SwiftUI

extension View {
    /// Sets up a SwiftUI text input for secret text, as `secretTextInput(_:)` does in the iOS app: no autocorrection,
    /// nothing learned from what's typed, and no Writing Tools. A Mac's keyboard doesn't capitalize, so there's nothing
    /// else to decide.
    ///
    /// Every text input in the app's sources declares it, and `SecretTextInputDeclarationTests` fails for any that
    /// doesn't.
    func secretTextInput() -> some View {
        autocorrectionDisabled()
            .writingToolsBehavior(.disabled)
    }
}
