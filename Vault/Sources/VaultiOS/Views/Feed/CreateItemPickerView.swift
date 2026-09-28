import Foundation
import SwiftUI

/// The first step of the new-item sheet: choosing what kind of item to make.
///
/// Laid out like the editor's steps that follow it in the same sheet, with the choices as cards on the sheet's glass,
/// and sized to fit, so choosing one slides on to that item's first step like the next step. It has no step header,
/// since the "New Item" title and the cards say enough, and no progress bar, since how many steps follow depends on
/// what's chosen.
@MainActor
struct CreateItemPickerView: View {
    var onSelect: (CreatingItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            option(
                .otpCode,
                title: "Code",
                subtitle: "2FA timer or counter based codes",
                systemImage: "qrcode",
            )
            option(
                .secureNote,
                title: "Note",
                subtitle: "Freeform text",
                systemImage: "text.alignleft",
            )
            option(
                .recoveryPhrase,
                title: "Recovery Phrase",
                subtitle: "Crypto wallet seed words",
                systemImage: "list.number",
            )
        }
        .listSectionSpacing(12)
        .environment(\.isInGuidedDetailEditor, true)
        // The sheet's glass shows through, as it does behind the steps that follow.
        .scrollContentBackground(.hidden)
        .reportsFittedSheetHeight()
        .navigationTitle("New Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .tint(.red)
                }
            }
        }
    }

    private func option(
        _ item: CreatingItem,
        title: String,
        subtitle: String,
        systemImage: String,
    ) -> some View {
        Section {
            Button {
                onSelect(item)
            } label: {
                OptionCardLabel(title: title, subtitle: subtitle, systemImage: systemImage)
                    .padding(.vertical, 6)
            }
        }
        .listRowBackground(DetailEditorRowBackground())
    }
}

#Preview {
    @Previewable @State var isPresented = true

    Color.clear
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                CreateItemPickerView { _ in
                    isPresented = false
                }
            }
        }
}
