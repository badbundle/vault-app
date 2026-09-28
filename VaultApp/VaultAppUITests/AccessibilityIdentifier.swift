/// The accessibility identifiers of the elements these tests use, as the views in `Vault/Sources/VaultiOS` set them.
///
/// Elements are found by these rather than by their text, which changes with the language.
enum AccessibilityIdentifier {
    enum Sidebar {
        static let items = "sidebar.items"
        static let settings = "sidebar.settings"
    }

    /// The cards in the feed, named by the kind of item.
    enum Feed {
        static let otpCode = "feed.item.otp-code"
        static let encryptedItem = "feed.item.encrypted-item"
    }

    enum Detail {
        static let done = "detail.done"
    }

    enum EncryptedItem {
        static let password = "encrypted-item.password"
        static let decrypt = "encrypted-item.decrypt"
        /// Shown in place of the prompt for the password when the password is wrong.
        static let error = "encrypted-item.error"
    }

    enum SecureNote {
        static let contents = "secure-note.contents"
    }

    enum Settings {
        static let list = "settings"
        /// The "Tap a Code To" picker, and its option to show a code's details.
        static let codeTapAction = "settings.code-tap-action"
        static let codeTapActionShowDetails = "settings.code-tap-action.showDetails"
    }
}
