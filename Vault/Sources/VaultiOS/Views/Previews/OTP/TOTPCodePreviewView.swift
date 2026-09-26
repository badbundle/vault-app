import Combine
import SwiftUI
import VaultFeed
import VaultKeygen

@MainActor
struct TOTPCodePreviewView<TimerBar: View>: View {
    var previewViewModel: OTPCodePreviewViewModel
    var timerView: TimerBar
    var behaviour: VaultItemViewBehaviour

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon at top
                icon
                    .padding(.bottom, 8)

                // Issuer and account labels
                labelsStack

                // Code section - prominent
                OTPPreviewCodeText(codeState: previewViewModel.code, behaviour: behaviour)
                    .padding(.vertical, 12)
            }
            // Not the bar: its label has to stay readable while editing, which the shimmer's fade would stop.
            .shimmering(active: isEditing)

            Spacer(minLength: 0)

            // Timer bar at bottom
            CodeStateTimerBarView(
                timerView: activeTimerView,
                codeState: previewViewModel.code,
                behaviour: behaviour,
            )
        }
        .padding(16)
        .animation(.snappy, value: behaviour)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fill)
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

    @ViewBuilder
    private var activeTimerView: some View {
        switch behaviour {
        case .normal:
            switch previewViewModel.code {
            case .visible, .locked:
                timerView
            case .finished, .notReady, .obfuscated:
                HorizontalTimerProgressBarView.empty
            case .error:
                HorizontalTimerProgressBarView.filled(.red)
            }
        case .editingState:
            HorizontalTimerProgressBarView.editing
        }
    }

    private var isEditing: Bool {
        switch behaviour {
        case .normal: false
        case .editingState: true
        }
    }
}

#Preview {
    let clock = EpochClockImpl()
    let injector = VaultInjector(
        clock: clock,
        intervalTimer: IntervalTimerImpl(),
        backupEventLogger: BackupEventLoggerMock(),
        vaultKeyDeriverFactory: VaultKeyDeriverFactoryImpl(),
        encryptedVaultDecoder: EncryptedVaultDecoderMock(),
        autoBackupService: AutoBackupServiceMock(status: .disabled, configuration: .init()),
        defaults: Defaults(userDefaults: .standard),
        fileManager: .default,
    )
    let codePublisher = OTPCodePublisherMock()
    let errorPublisher = OTPCodePublisherMock()
    let finishedPublisher = OTPCodePublisherMock()
    let subject = PassthroughSubject<OTPCodeTimerState, Never>()

    @MainActor
    func makePreview(
        issuer: String,
        codePublisher: OTPCodePublisherMock,
        behaviour: VaultItemViewBehaviour = .normal,
    ) -> some View {
        let previewViewModel = OTPCodePreviewViewModel(
            accountName: "test@example.com",
            issuer: issuer,
            color: .default,
            isLocked: false,
            codePublisher: codePublisher,
        )
        return TOTPCodePreviewView(
            previewViewModel: previewViewModel,
            timerView: CodeTimerHorizontalBarView(
                timerState: OTPCodeTimerPeriodState(statePublisher: subject.eraseToAnyPublisher()),
                color: .blue,
            ),
            behaviour: behaviour,
        )
    }

    return ScrollView(.vertical) {
        makePreview(issuer: "Working Example", codePublisher: codePublisher)
            .onAppear {
                codePublisher.subject.send("1234567")
            }

        makePreview(issuer: "Working Example with Very long title and stuff", codePublisher: codePublisher)
            .onAppear {
                codePublisher.subject.send("1234567")
            }

        makePreview(issuer: "", codePublisher: codePublisher)

        makePreview(issuer: "Code Error Example", codePublisher: errorPublisher)
            .onAppear {
                errorPublisher.subject.send(completion: .failure(NSError(domain: "sdf", code: 1)))
            }

        makePreview(issuer: "Finished Example", codePublisher: finishedPublisher)
            .onAppear {
                finishedPublisher.subject.send(completion: .finished)
            }

        makePreview(issuer: "Obfuscated", codePublisher: codePublisher, behaviour: .editingState(message: "Editing..."))
            .onAppear {
                finishedPublisher.subject.send(completion: .finished)
            }

        makePreview(issuer: "Obfuscated (no msg)", codePublisher: codePublisher, behaviour: .editingState(message: nil))
            .onAppear {
                finishedPublisher.subject.send(completion: .finished)
            }
    }
    .padding()
    .padding()
    .environment(injector)
    .onAppear {
        subject.send(.init(startTime: 15, endTime: 100))
    }
}
