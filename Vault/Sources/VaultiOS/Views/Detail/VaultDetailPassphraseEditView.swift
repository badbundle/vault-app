import Foundation
import SwiftUI
import VaultFeed

struct VaultDetailPassphraseEditView: View {
    var title: String
    var description: String
    var hiddenWithPassphraseTitle: String
    @Binding var viewConfig: VaultItemViewConfiguration
    @Binding var passphrase: String

    var body: some View {
        Form {
            titleSection
            optionSection
        }
        .animation(.snappy, value: viewConfig.isEnabled)
        .transition(.move(edge: .top))
    }

    private var titleSection: some View {
        Section {
            PlaceholderView(
                systemIcon: viewConfig.isEnabled ? "eye.slash" : "eye.fill",
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
            Toggle(isOn: $viewConfig.isEnabled) {
                Text("Hide with passphrase")
                    .font(.body)
            }
            if viewConfig.isEnabled {
                FormRow(image: Image(systemName: "textformat"), color: .secondary, style: .standard) {
                    TextField("Enter passphrase...", text: $passphrase)
                        .keyboardType(.default)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .textInputAutocapitalization(.never)
                }
            }
        } footer: {
            if viewConfig.isEnabled {
                Text(hiddenWithPassphraseTitle)
            }
        }
    }
}

#Preview {
    VaultDetailPassphraseEditView(
        title: "Test",
        description: "Test",
        hiddenWithPassphraseTitle: "nice",
        viewConfig: .constant(.requiresSearchPassphrase),
        passphrase: .constant("nice"),
    )
}
