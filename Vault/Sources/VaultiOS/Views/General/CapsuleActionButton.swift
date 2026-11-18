import Foundation
import SwiftUI

/// Label for the filled capsule button of a screen that has no form to put a row in: the lock screen's Unlock, and
/// the Danger Zone's confirmation bar.
///
/// A `Form` never uses this. Its actions are `FormActionRow`s.
struct CapsuleActionLabel: View {
    var title: String
    var systemImage: String
    var isLoading: Bool

    init(_ title: String, systemImage: String, isLoading: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
    }

    var body: some View {
        HStack {
            Text(title)
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity)
        // Keep the capsule the same size while loading: hide the label under the spinner.
        .opacity(isLoading ? 0 : 1)
        .overlay {
            if isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

extension View {
    /// Styles a `Button` as a full-width filled capsule, for a `CapsuleActionLabel`.
    func capsuleActionButton() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}
