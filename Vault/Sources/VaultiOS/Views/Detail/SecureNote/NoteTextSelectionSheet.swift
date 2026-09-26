import Foundation
import SwiftUI

/// A formatted note's text as it was written, to select part of it and copy.
///
/// A formatted note is drawn by MarkdownUI, whose text can only be selected with the system's copy, which skips the
/// clipboard settings. Here it's a `SelectableText`, so a copy follows them like any other copy of a note.
struct NoteTextSelectionSheet: View {
    var text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SelectableText(text, fontStyle: .normal, textStyle: .body, copyingAs: .note)
                    .padding(.horizontal, 4)
                    // Where the note starts, rather than centered when its lines are all short.
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Select Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                }
            }
        }
        // Half height suits most notes, and a long one can be pulled up.
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            NoteTextSelectionSheet(text: "# Home Wi-Fi\n\nNetwork: **Guest**\nPassword: correct horse battery staple")
        }
}
