import Foundation

enum CreatingItem {
    case otpCode
    case secureNote
    case recoveryPhrase
    case privateKey

    /// The kinds of item in the order every add flow offers them: the new-item sheet and the empty feed.
    ///
    /// Recovery phrases and private keys come first, as they're what Vault is for, and a new person's first view
    /// should point at them.
    static let addOrder: [CreatingItem] = [.recoveryPhrase, .privateKey, .secureNote, .otpCode]

    var title: String {
        switch self {
        case .recoveryPhrase: "Recovery Phrase"
        case .privateKey: "Private Key"
        case .secureNote: "Note"
        case .otpCode: "Code"
        }
    }

    var subtitle: String {
        switch self {
        case .recoveryPhrase: "Seed words for a crypto wallet"
        case .privateKey: "A wallet's private or extended key, or a PGP or SSH key"
        case .secureNote: "Any text, like a PIN or a password"
        case .otpCode: "Two-factor codes for websites and apps"
        }
    }

    var systemImage: String {
        switch self {
        case .recoveryPhrase: "list.number"
        case .privateKey: "key.fill"
        case .secureNote: "text.alignleft"
        case .otpCode: "qrcode"
        }
    }
}
