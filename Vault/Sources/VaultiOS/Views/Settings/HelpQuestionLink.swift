import Foundation
import SwiftUI

/// A form row, worded as a question, that opens a help page.
struct HelpQuestionLink<Destination: View>: View {
    var question: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            FormRow(image: Image(systemName: "questionmark.circle"), color: .blue, style: .standard) {
                Text(question)
            }
        }
    }
}
