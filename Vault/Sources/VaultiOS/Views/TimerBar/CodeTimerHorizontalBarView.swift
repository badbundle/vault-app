import Combine
import SwiftUI
import UniformTypeIdentifiers
import VaultFeed

@MainActor
struct CodeTimerHorizontalBarView: View {
    var timerState: OTPCodeTimerPeriodState
    var color: Color = .accentColor
    var backgroundColor: Color = .init(.quaternarySystemFill)

    @State private var currentFractionCompleted = 1.0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(VaultInjector.self) private var injector
    @State private var resetTimerBarAnimation: DispatchWorkItem?
    @State private var timerAnimation: DispatchWorkItem?

    var body: some View {
        GeometryReader { proxy in
            HorizontalTimerProgressBarView(
                fractionCompleted: currentFractionCompleted,
                color: color,
                backgroundColor: backgroundColor,
            )
            .onChange(of: proxy.size) { _, _ in
                // the size of the viewport has changed
                resetAnimation(animateReset: false)
            }
        }
        .onChange(of: timerState.animationState) { _, _ in
            resetAnimation(animateReset: true)
        }
        .onAppear {
            // we have just appeared onscreen
            resetAnimation(animateReset: false)
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            // we have appeared from background
            if newScenePhase == .active {
                resetAnimation(animateReset: false)
            }
        }
    }

    private func resetAnimation(animateReset: Bool) {
        let clock = injector.clock
        resetTimerBarAnimation?.cancel()
        timerAnimation?.cancel()
        resetTimerBarAnimation = .init(qos: .userInteractive) {
            withAnimation(
                .linear(duration: animateReset ? 0.15 : 0),
                completionCriteria: .removed,
            ) {
                currentFractionCompleted = timerState.animationState.initialFraction(currentTime: clock.currentTime)
            } completion: {
                if case let .animate(state) = timerState.animationState {
                    timerAnimation = .init(qos: .userInteractive) {
                        withAnimation(.linear(duration: state.remainingTime(at: clock.currentTime))) {
                            currentFractionCompleted = 0
                        }
                    }
                    timerAnimation?.perform()
                }
            }
        }
        resetTimerBarAnimation?.perform()
    }
}

#Preview("View", traits: .sizeThatFitsLayout) {
    let subject: PassthroughSubject<OTPCodeTimerState, Never> = .init()
    return CodeTimerHorizontalBarView(
        timerState: OTPCodeTimerPeriodState(statePublisher: subject.eraseToAnyPublisher()),
    )
    .frame(width: 250, height: 20)
    .onAppear {
        subject.send(OTPCodeTimerState(startTime: 23, endTime: 60))
    }
    .environment(VaultInjector(
        clock: EpochClockMock(currentTime: 30),
        intervalTimer: IntervalTimerImpl(),
        backupEventLogger: BackupEventLoggerMock(),
        vaultKeyDeriverFactory: VaultKeyDeriverFactoryImpl(),
        encryptedVaultDecoder: EncryptedVaultDecoderMock(),
        autoBackupService: AutoBackupServiceMock(status: .disabled, configuration: .init()),
        defaults: Defaults(userDefaults: .standard),
        fileManager: .default,
    ))
}
