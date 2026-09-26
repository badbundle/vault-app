import Foundation
import SwiftUI

extension EnvironmentValues {
    /// Whether the editor is walking through its steps, where the rows sit on the sheet's glass like the new-item
    /// picker's cards, rather than on the usual grouped background.
    @Entry var isInGuidedDetailEditor = false
}

/// The background of a row in an item's editor, optionally tinted to pick the row out.
///
/// A row that sets its own background in place of the editor's should use this, so it matches the rows around it.
struct DetailEditorRowBackground: View {
    var tint: Color?

    @Environment(\.isInGuidedDetailEditor) private var isGuided

    var body: some View {
        ZStack {
            if isGuided {
                Rectangle().fill(.fill.quaternary)
            } else {
                Color(uiColor: .secondarySystemGroupedBackground)
            }
            if let tint {
                tint.opacity(0.2)
            }
        }
    }
}
