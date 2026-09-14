import SwiftUI
import VaultFeed

struct VaultDetailNotePreviewEditView: View {
    var title: String
    var description: String
    var isEncrypted: Bool
    @Binding var previewMode: NotePreviewMode

    private var availableModes: [NotePreviewMode] {
        if isEncrypted {
            NotePreviewMode.allCases.filter { $0 != .titleAndFirstLine }
        } else {
            NotePreviewMode.allCases
        }
    }

    var body: some View {
        Form {
            titleSection
            optionSection
        }
        .animation(.snappy, value: previewMode)
        .transition(.move(edge: .top))
        .onAppear {
            if !availableModes.contains(previewMode) {
                previewMode = availableModes.first ?? .titleOnly
            }
        }
    }

    private var titleSection: some View {
        Section {
            PlaceholderView(
                systemIcon: previewMode.systemIconName,
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
            Picker(selection: $previewMode) {
                ForEach(availableModes, id: \.self) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            } label: {
                Text("Preview style")
                    .font(.body)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

extension NotePreviewMode {
    fileprivate var systemIconName: String {
        switch self {
        case .titleAndFirstLine: "text.alignleft"
        case .titleOnly: "text.line.first.and.arrowtriangle.forward"
        case .hidden: "eye.slash.fill"
        }
    }
}

#Preview {
    VaultDetailNotePreviewEditView(
        title: "Preview",
        description: "Choose what shows in the preview tile.",
        isEncrypted: false,
        previewMode: .constant(.titleAndFirstLine),
    )
}

#Preview("Encrypted") {
    VaultDetailNotePreviewEditView(
        title: "Preview",
        description: "Choose what shows in the preview tile.",
        isEncrypted: true,
        previewMode: .constant(.titleOnly),
    )
}
