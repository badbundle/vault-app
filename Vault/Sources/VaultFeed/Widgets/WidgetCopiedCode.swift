import Foundation
import notify

/// A code a Mac widget copied, which the app clears from the clipboard as it clears its own copies (G87): once the
/// Clear Clipboard time is up, or when Vault locks or quits, unless something else has been copied since.
///
/// AppKit's clipboard has no expiry date, and the widget extension doesn't run long enough to clear it, so it leaves
/// the app this note (`WidgetCopiedCodeStore`). The app is running and unlocked whenever a widget has a code to copy.
/// It holds nothing of the code.
public struct WidgetCopiedCode: Codable, Equatable, Sendable {
    /// The clipboard's change count once the code was on it. Anything copied since changes it.
    public var changeCount: Int
    /// When the code was copied, which the Clear Clipboard time counts from.
    public var copiedAt: Date

    public init(changeCount: Int, copiedAt: Date) {
        self.changeCount = changeCount
        self.copiedAt = copiedAt
    }
}

/// Where a Mac widget leaves the app a note of the code it copied: a keychain item in the widgets' keychain access
/// group (`WidgetKeychainItem.copiedCode`), as the widget extension has no App Group. It tells the app with a Darwin
/// notification, which a sandboxed extension can post with no App Group. The app also looks for a note whenever it
/// becomes active, locks, quits or launches, in case it didn't hear.
///
/// Any process can post the notification, but that only has the app look for a note, which only the app and the
/// widget extension can write.
public struct WidgetCopiedCodeStore: Sendable {
    /// The Darwin notification the widget posts once it's left a note.
    public static let notificationName = "com.badbundle.vault.widgets.copied-code"

    private let keychain: any WidgetKeychainStoring
    private let notify: @Sendable () -> Void

    /// - Parameter notify: Tells the app there's a note.
    public init(
        keychain: any WidgetKeychainStoring = WidgetKeychainItem.copiedCode,
        notify: @escaping @Sendable () -> Void = { notify_post(Self.notificationName) },
    ) {
        self.keychain = keychain
        self.notify = notify
    }

    /// Leaves the app a note of `copy`, in place of any before it, and tells it.
    public func leave(_ copy: WidgetCopiedCode) throws {
        try keychain.save(JSONEncoder().encode(copy))
        notify()
    }

    /// The note the widget last left, if the app hasn't taken it yet. It's gone once it's taken.
    public func take() -> WidgetCopiedCode? {
        guard let data = try? keychain.read() else { return nil }
        try? keychain.remove()
        return try? JSONDecoder().decode(WidgetCopiedCode.self, from: data)
    }

    /// Deletes the note, as an erase does, which tries again if it can't.
    public func remove() throws {
        try keychain.remove()
    }
}
