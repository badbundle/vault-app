import AppKit
import Foundation
import notify
import VaultFeed

/// Hears of each code a Mac widget copies, and has Vault's clipboard clear it as it clears its own (G87): once the
/// Clear Clipboard time is up, or when Vault locks or quits, unless something else has been copied since.
///
/// The widget extension can't clear the clipboard later, so it leaves a note in the widgets' keychain access group
/// (`WidgetCopiedCodeStore`), and posts a Darwin notification. The app takes the note when it hears that, and whenever
/// it becomes active, locks, quits or launches, in case it didn't. The app is running and unlocked whenever a widget
/// has a code to copy. It listens for as long as the app runs.
@MainActor
final class VaultMacWidgetCopies {
    private let notes: WidgetCopiedCodeStore
    private let pasteboard: VaultMacPasteboard
    private let notificationName: String
    private var notifyToken = NOTIFY_TOKEN_INVALID
    private var activation: (any NSObjectProtocol)?

    /// - Parameter notificationName: The Darwin notification the widget posts: tests post their own.
    init(
        notes: WidgetCopiedCodeStore,
        pasteboard: VaultMacPasteboard,
        notificationName: String = WidgetCopiedCodeStore.notificationName,
    ) {
        self.notes = notes
        self.pasteboard = pasteboard
        self.notificationName = notificationName
    }

    /// Takes over each code a widget copies from now on, and any copied before.
    func start(notificationCenter: NotificationCenter = .default) {
        notify_register_dispatch(notificationName, &notifyToken, .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.takeOver()
            }
        }
        activation = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.takeOver()
            }
        }
        takeOver()
    }

    /// Takes over clearing the code a widget last copied, if there's one the app hasn't yet: as Vault locks or quits,
    /// in case it hasn't heard of it.
    func takeOver() {
        guard let copy = notes.take() else { return }
        pasteboard.adoptWidgetCopy(copy)
    }
}
