import UIKit
import VaultFeed

extension VaultBackgroundTime {
    /// Background time from `UIApplication`, for converting the plain store and rekeying the vault.
    public static let application = VaultBackgroundTime { @MainActor in
        let task = ApplicationBackgroundTask()
        return { await task.end() }
    }
}

/// One background task. Ending it twice, once when its time runs out and once when the work finishes, ends it once.
@MainActor
private final class ApplicationBackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Vault storage change") { [weak self] in
            // The expiration handler runs on the main thread.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
