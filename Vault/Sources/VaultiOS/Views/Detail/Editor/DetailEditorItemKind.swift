import Foundation
import VaultFeed

/// The kind of item an editor is for, which decides how its steps are worded.
enum DetailEditorItemKind {
    case code
    case note
    case recoveryPhrase

    /// The editor's last button when creating an item.
    var addTitle: String {
        switch self {
        case .code: "Add Code"
        case .note: "Add Note"
        case .recoveryPhrase: "Add Phrase"
        }
    }
}

extension DetailEditorStep {
    func title(for kind: DetailEditorItemKind) -> String {
        switch (self, kind) {
        case (.content, .code): "Key"
        case (.content, .note): "Note"
        case (.content, .recoveryPhrase): "Words"
        case (.details, _): "Name"
        case (.appearance, _): "Appearance"
        case (.security, _): "Privacy & Security"
        }
    }

    /// One line on what the step is for, under its title.
    func subtitle(for kind: DetailEditorItemKind) -> String {
        switch (self, kind) {
        case (.content, .code):
            "Scan the QR code the site shows you, or enter its setup key."
        case (.content, .note):
            "Write anything you want to keep safe. The first line is the note's title."
        case (.content, .recoveryPhrase):
            "Enter the words in order. They're encrypted with a password you choose."
        case (.details, .recoveryPhrase):
            "A title to recognize the phrase by. The description is encrypted with the words."
        case (.details, _):
            "What it's called in your vault and in search."
        case (.appearance, _):
            "A color and tags to help you find it at a glance."
        case (.security, _):
            "Choose who can see it, and how it's protected."
        }
    }

    func systemImage(for kind: DetailEditorItemKind) -> String {
        switch (self, kind) {
        case (.content, .code): "qrcode.viewfinder"
        case (.content, .note): "text.alignleft"
        case (.content, .recoveryPhrase): "list.number"
        case (.details, _): "character.cursor.ibeam"
        case (.appearance, _): "paintpalette.fill"
        case (.security, _): "lock.shield.fill"
        }
    }
}
