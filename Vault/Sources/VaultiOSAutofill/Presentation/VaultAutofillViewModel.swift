import Combine
import Foundation
import VaultFeed
import VaultSettings

@MainActor
@Observable
final class VaultAutofillViewModel {
    enum DisplayedFeature: Equatable {
        case setupConfiguration
        case showAllCodesSelector
        case unimplemented(String)
    }

    enum RequestCancelReason: Equatable {
        case userCancelled
    }

    private(set) var feature: DisplayedFeature?
    let localSettings: LocalSettings
    /// The extension's own copy of the app lock: each time the extension comes up with the lock on, it starts locked.
    let appLock: AppLockService

    init(
        localSettings: LocalSettings,
        appLock: AppLockService,
    ) {
        self.localSettings = localSettings
        self.appLock = appLock
    }

    func show(feature: DisplayedFeature) {
        self.feature = feature
    }

    let configurationDismissSubject = PassthroughSubject<Void, Never>()

    var configurationDismissPublisher: any Publisher<Void, Never> {
        configurationDismissSubject
    }

    let textToInsertSubject = PassthroughSubject<String, Never>()

    var textToInsertPublisher: some Publisher<String, Never> {
        // Don't insert empty strings.
        textToInsertSubject.filter(\.isNotBlank)
    }

    let cancelRequestSubject = PassthroughSubject<RequestCancelReason, Never>()

    var cancelRequestPublisher: some Publisher<RequestCancelReason, Never> {
        cancelRequestSubject
    }

    func dismissConfiguration() {
        configurationDismissSubject.send()
    }
}
