import Foundation
import SwiftUI

/// Modifer to the visual behaviour of an OTP view.
///
/// This takes precedant over any content the view is currently displaying.
public enum VaultItemViewBehaviour: Equatable {
    /// Standard behaviour, the code should show the content it wants.
    case normal
    /// The item is in an "edit" state.
    /// Content may be modified to make it clear that an editing action is in progress.
    case editingState(message: String?)
}

extension EnvironmentValues {
    /// Whether a code's preview shows just the code and its timer, rather than its whole card.
    ///
    /// For the code's own page, whose badge already shows the icon and names from the card.
    @Entry var showsCodeOnly = false
}
