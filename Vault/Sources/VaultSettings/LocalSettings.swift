import Combine
import Foundation
import FoundationExtensions

@MainActor
@Observable
public final class LocalSettings {
    public var state: LocalSettingsState

    /// - Parameters:
    ///   - defaults: The app's own defaults, where most settings are kept.
    ///   - sharedDefaults: The defaults the app shares with its extensions, for the settings they read too.
    public init(defaults: Defaults, sharedDefaults: Defaults) {
        state = LocalSettingsState(defaults: defaults, sharedDefaults: sharedDefaults)
    }

    /// Keeps every setting in `defaults`, for previews and tests that have no extensions to share with.
    public convenience init(defaults: Defaults) {
        self.init(defaults: defaults, sharedDefaults: defaults)
    }
}
