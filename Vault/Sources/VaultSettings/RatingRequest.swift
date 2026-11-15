import Foundation

/// Vault on the App Store.
public enum VaultAppStore {
    /// Vault's App Store ID, the same for the iPhone, iPad and Mac app.
    public static let appID = "6738931366"

    /// Vault's App Store page, opened at Write a Review. On the Mac it opens in the App Store rather than a browser.
    public static let writeReviewURL: URL = {
        #if os(macOS)
        let scheme = "macappstore"
        #else
        let scheme = "https"
        #endif
        return URL(string: "\(scheme)://apps.apple.com/app/id\(appID)?action=write-review")!
    }()
}

/// Says when Vault may ask for a rating with Apple's prompt: once each time the app is opened, at most, and Apple
/// then decides whether the prompt shows (no more than three times a year).
///
/// It remembers only that it asked in this launch, in memory, and saves nothing: not in a vault, the preferences or
/// the keychain. A saved record of asking would say that someone kept or checked a backup, and when, to anyone with a
/// copy of Vault's files, and one kept outside the vaults would say it of a vault other than the one that's open
/// (docs/security-model.md, G107). So don't give it anything to save to.
@MainActor
public final class RatingRequestPolicy {
    private let isEnabled: Bool
    private var hasAsked = false

    /// - Parameter isEnabled: `false` never asks, as for the App Store screenshots and the UI tests.
    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Whether to ask now. `true` once, the first time it's called, then `false` until the app is opened again.
    public func shouldAsk() -> Bool {
        guard isEnabled, !hasAsked else { return false }
        hasAsked = true
        return true
    }
}
