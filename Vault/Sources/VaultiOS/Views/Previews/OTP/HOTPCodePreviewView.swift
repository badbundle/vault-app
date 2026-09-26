import SwiftUI
import VaultFeed

@MainActor
struct HOTPCodePreviewView<ButtonView: View>: View {
    var buttonView: ButtonView
    var previewViewModel: OTPCodePreviewViewModel
    var behaviour: VaultItemViewBehaviour

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon at top
            icon
                .padding(.bottom, 8)

            // Issuer and account labels
            labelsStack

            // Code section - prominent
            OTPPreviewCodeText(codeState: previewViewModel.code, behaviour: behaviour)
                .padding(.vertical, 12)

            Spacer(minLength: 0)

            // Timer bar and button at bottom
            timerSection
        }
        .padding(16)
        .animation(.snappy, value: behaviour)
        .animation(.snappy, value: canLoadNextCode)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fill)
        .shimmering(active: isEditing)
        .modifier(
            VaultCardModifier(
                configuration: .init(
                    style: isEditing ? .prominent : .secondary,
                    border: previewViewModel.color.color,
                    padding: .init(),
                ),
            ),
        )
    }

    @ViewBuilder
    private var activeTimerView: some View {
        switch behaviour {
        case .normal:
            switch previewViewModel.code {
            case .visible, .locked:
                Color.accentColor
            case .notReady, .obfuscated:
                Color(.quaternarySystemFill)
            case .error, .finished:
                Color.red
            }
        case .editingState:
            Color.accentColor
        }
    }

    private var labelsStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            VaultCardTitle(text: previewViewModel.visibleIssuer, isEditing: isEditing, lineLimit: 2)

            Text(accountNameFormatted)
                .font(.caption2)
                .foregroundStyle(isEditing ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountNameFormatted: String {
        if previewViewModel.accountName.isNotEmpty {
            previewViewModel.accountName
        } else {
            localized(key: "code.accountNamePlaceholder")
        }
    }

    @ViewBuilder
    private var icon: some View {
        if case .error = previewViewModel.code {
            PreviewErrorIcon()
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isEditing ? .white.opacity(0.8) : previewViewModel.color.color.opacity(0.7))
        } else {
            Image(systemName: "key.horizontal.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isEditing ? .white.opacity(0.8) : previewViewModel.color.color.opacity(0.7))
        }
    }

    private var timerSection: some View {
        HStack(alignment: .bottom, spacing: 4) {
            CodeStateTimerBarView(
                timerView: activeTimerView,
                codeState: previewViewModel.code,
                behaviour: behaviour,
            )
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            buttonView
                .disabled(!canLoadNextCode)
        }
        // The row takes only the bar's height, with the taller refresh button
        // rising into the space above it, so the rest of the card has exactly
        // the room it has in a TOTP card and lays out the same way.
        .frame(height: 12, alignment: .bottom)
        .animation(.snappy, value: canLoadNextCode)
    }

    private var canLoadNextCode: Bool {
        previewViewModel.code.allowsNextCodeToBeGenerated && behaviour == .normal
    }

    private var isEditing: Bool {
        switch behaviour {
        case .normal: false
        case .editingState: true
        }
    }
}

#Preview {
    let codePublisher = OTPCodePublisherMock()
    let finishedPublisher = OTPCodePublisherMock()
    let errorPublisher = OTPCodePublisherMock()

    @MainActor
    func makePreviewView(
        accountName: String,
        codePublisher: OTPCodePublisherMock,
        behaviour: VaultItemViewBehaviour = .normal,
    ) -> some View {
        let previewViewModel = OTPCodePreviewViewModel(
            accountName: accountName,
            issuer: "Authority",
            color: .default,
            isLocked: false,
            codePublisher: codePublisher,
        )
        return HOTPCodePreviewView(
            buttonView: OTPCodeButtonView(
                viewModel: .init(
                    id: .new(),
                    codePublisher: .init(
                        hotpGenerator: .init(secret: Data()),
                    ),
                    timer: IntervalTimerImpl(),
                    initialCounter: 0,
                    incrementerStore: VaultStoreHOTPIncrementerMock(),
                ),
            ),
            previewViewModel: previewViewModel,
            behaviour: behaviour,
        )
    }

    return ScrollView(.vertical) {
        makePreviewView(accountName: "Normal", codePublisher: codePublisher)
            .onAppear {
                codePublisher.subject.send("123456")
            }

        makePreviewView(accountName: "Finished", codePublisher: finishedPublisher)
            .onAppear {
                finishedPublisher.subject.send(completion: .finished)
            }

        makePreviewView(accountName: "Error", codePublisher: errorPublisher)
            .onAppear {
                errorPublisher.subject.send(completion: .failure(NSError(domain: "any", code: 100)))
            }

        makePreviewView(
            accountName: "Obfuscate",
            codePublisher: codePublisher,
            behaviour: .editingState(message: "editing"),
        )

        makePreviewView(
            accountName: "Obfuscate (no msg)",
            codePublisher: codePublisher,
            behaviour: .editingState(message: nil),
        )
    }
    .padding(.horizontal, 32)
}
