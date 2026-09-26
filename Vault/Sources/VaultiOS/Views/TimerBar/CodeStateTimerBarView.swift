import Foundation
import SwiftUI
import UIKit
import VaultFeed

/// The bar at the bottom of a code card, labelled with the code's state when there's something to say about it.
///
/// The bar draws the label itself, so that it can color the label to suit whatever is behind it.
struct CodeStateTimerBarView<Timer: View>: View {
    var timerView: Timer
    var codeState: OTPCodeState
    var behaviour: VaultItemViewBehaviour

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        timerView
            .transition(.blurReplace())
            .environment(\.timerBarLabel, textToDisplay)
            .frame(height: CodeStateTimerBarMetrics.height(for: dynamicTypeSize))
            .clipShape(Capsule())
            .animation(.snappy, value: behaviour)
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

/// Sizes for the bar at the bottom of a code card and its label.
enum CodeStateTimerBarMetrics {
    /// The largest text size the bar and its label grow to. Beyond this the bar would crowd the card.
    static let largestDynamicTypeSize = DynamicTypeSize.xxxLarge

    /// The bar's height: 12 points at the default text size, growing with Dynamic Type so its label always fits.
    static func height(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        scaled(12, for: dynamicTypeSize)
    }

    /// The label's font size, which leaves room above and below it in a bar of ``height(for:)``.
    static func labelFontSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        scaled(8, for: dynamicTypeSize)
    }

    private static func scaled(_ value: CGFloat, for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let size = min(dynamicTypeSize, largestDynamicTypeSize)
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        return UIFontMetrics(forTextStyle: .caption2).scaledValue(for: value, compatibleWith: traits)
    }
}

extension EnvironmentValues {
    /// The message a code card's timer bar shows over its progress, such as "Code expired".
    ///
    /// Set by ``CodeStateTimerBarView`` and drawn by the ``HorizontalTimerProgressBarView`` inside it, which
    /// knows where its fill ends.
    @Entry var timerBarLabel: String?
}
