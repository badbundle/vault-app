import Foundation
import SwiftUI
import VaultFeed

/// Edit affordance for the per-item killphrase.
///
/// The plaintext killphrase is never shown — the persisted form is a one-way
/// digest, so the UI can only ask "is one set?" (the toggle) and "type a
/// new one to set/replace" (the field). Leaving the field empty while the
/// toggle stays on is treated as "leave the existing digest alone".
struct VaultDetailKillphraseEditView: View {
    var title: String
    var description: String
    var hiddenWithKillphraseTitle: String
    @Binding var killphraseEnabled: Bool
    @Binding var newKillphrase: String

    init(
        title: String,
        description: String,
        hiddenWithKillphraseTitle: String,
        killphraseEnabled: Binding<Bool>,
        newKillphrase: Binding<String>,
    ) {
        self.title = title
        self.description = description
        self.hiddenWithKillphraseTitle = hiddenWithKillphraseTitle
        _killphraseEnabled = killphraseEnabled
        _newKillphrase = newKillphrase
    }

    var body: some View {
        Form {
            titleSection
            optionSection
        }
        .animation(.snappy, value: killphraseEnabled)
        .transition(.move(edge: .top))
        .onChange(of: killphraseEnabled) { _, newValue in
            if !newValue {
                newKillphrase = ""
            }
        }
    }

    private var titleSection: some View {
        Section {
            PlaceholderView(
                systemIcon: killphraseEnabled ? "bolt.badge.checkmark.fill" : "bolt",
                title: title,
                subtitle: description,
            )
            .padding()
            .containerRelativeFrame(.horizontal)
            .contentTransition(.symbolEffect(.replace))
        }
    }

    private var optionSection: some View {
        Section {
            Toggle(isOn: $killphraseEnabled) {
                Text("Enable killphrase")
                    .font(.body)
            }

            if killphraseEnabled {
                FormRow(image: Image(systemName: "textformat"), color: .secondary, style: .standard) {
                    TextField("Set new killphrase...", text: $newKillphrase)
                        .keyboardType(.default)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .textInputAutocapitalization(.never)
                }
            }
        } footer: {
            if killphraseEnabled {
                Text(hiddenWithKillphraseTitle)
            }
        }
    }
}

#Preview {
    @Previewable @State var enabled = true
    @Previewable @State var newPhrase = ""
    return VaultDetailKillphraseEditView(
        title: "Test",
        description: "This is a test",
        hiddenWithKillphraseTitle: "This will be killed",
        killphraseEnabled: $enabled,
        newKillphrase: $newPhrase,
    )
}
