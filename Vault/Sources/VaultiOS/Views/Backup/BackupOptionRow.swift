import Foundation
import SwiftUI

/// One way to export or import, as a row that says what it does, in the style of the rows on the Backups screen.
struct BackupOptionRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            FormRow(image: Image(systemName: systemImage), color: color) {
                HStack {
                    TextAndSubtitle(title: title, subtitle: detail)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .tint(.primary)
    }
}
