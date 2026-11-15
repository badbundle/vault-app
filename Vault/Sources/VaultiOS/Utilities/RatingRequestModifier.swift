import StoreKit
import SwiftUI
import VaultSettings

extension EnvironmentValues {
    /// Whether Vault may ask for a rating. `nil` never asks, as in previews, tests and the extensions.
    @Entry var ratingRequestPolicy: RatingRequestPolicy?
}

extension View {
    /// Asks for a rating with Apple's prompt, a moment after `succeeded` becomes true, if the policy allows it.
    ///
    /// For the end of something that went well and took some care, such as saving a backup. Leaving the screen within
    /// that moment asks nothing.
    func asksForRating(after succeeded: Bool) -> some View {
        modifier(RatingRequestModifier(succeeded: succeeded))
    }
}

private struct RatingRequestModifier: ViewModifier {
    let succeeded: Bool
    @Environment(\.requestReview) private var requestReview
    @Environment(\.ratingRequestPolicy) private var policy

    /// Long enough to read what the screen says first.
    private static let delay: Duration = .seconds(2)

    func body(content: Content) -> some View {
        content.task(id: succeeded) {
            guard succeeded, policy != nil else { return }
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let policy, policy.shouldAsk() else { return }
            requestReview()
        }
    }
}
