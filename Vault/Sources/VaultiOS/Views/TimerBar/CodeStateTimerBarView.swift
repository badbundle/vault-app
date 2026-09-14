import Foundation
import SwiftUI
import VaultFeed

struct CodeStateTimerBarView<Timer: View>: View {
    var timerView: Timer
    var codeState: OTPCodeState
    var behaviour: VaultItemViewBehaviour

    var body: some View {
        ZStack(alignment: .leading) {
            timerView
                .transition(.blurReplace())

            if let textToDisplay {
                LoadingBarLabel(text: textToDisplay)
                    .shimmering(active: isShimmering)
            }
        }
        .animation(.snappy, value: behaviour)
    }

    private var isShimmering: Bool {
        switch behaviour {
        case .normal: false
        case .editingState: true
        }
    }

    private var textToDisplay: String? {
        switch behaviour {
        case let .editingState(message):
            message
        case .normal:
            switch codeState {
            case let .obfuscated(obfuscationReason):
                switch obfuscationReason {
                case .expiry:
                    localized(key: "code.updateRequired")
                case .privacy:
                    nil
                }
            case let .error(presentationError, _):
                presentationError.userTitle
            case .locked:
                "Code locked"
            case .visible, .notReady, .finished:
                nil
            }
        }
    }
}
