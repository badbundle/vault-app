import SwiftUI
import VaultFeed

struct VaultDetailLockEditView: View {
    var title: String
    var description: String
    @Binding var lockState: VaultItemLockState

    var body: some View {
        Form {
            titleSection
            optionSection
        }
        .animation(.snappy, value: lockState)
        .transition(.move(edge: .top))
    }

    private var titleSection: some View {
        Section {
            PlaceholderView(
                systemIcon: lockState.isLocked ? "lock.fill" : "lock.open.fill",
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
            Toggle(isOn: $lockState.isLocked) {
                Text("Lock item")
                    .font(.body)
            }
        } footer: {
            Text(lockState.localizedSubtitle)
        }
    }
}

#Preview {
    VaultDetailLockEditView(title: "Hello", description: "Hello world", lockState: .constant(.lockedWithNativeSecurity))
}
