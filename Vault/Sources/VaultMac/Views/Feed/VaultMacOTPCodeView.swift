import SwiftUI
import VaultFeed

/// A code's digits, in groups, monospaced: hidden as dots while it's locked or not ready.
struct VaultMacOTPCodeText: View {
    var state: OTPCodeState
    var font: Font

    var body: some View {
        Text(text)
            .font(font.monospacedDigit())
            .foregroundStyle(isError ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .contentTransition(.numericText())
            .accessibilityLabel(accessibilityText)
    }

    private var text: String {
        switch state {
        case let .visible(code): Self.grouped(code)
        case let .locked(code): Self.grouped(String(repeating: "•", count: code.count))
        case let .error(_, digits): Self.grouped(String(repeating: "•", count: digits))
        case .notReady, .finished, .obfuscated: Self.grouped(String(repeating: "•", count: 6))
        }
    }

    private var isError: Bool {
        if case .error = state {
            true
        } else {
            false
        }
    }

    private var accessibilityText: String {
        switch state {
        case let .visible(code): code.map(String.init).joined(separator: " ")
        case .locked: "Locked"
        case .error: "Code unavailable"
        case .notReady, .finished, .obfuscated: "Code hidden"
        }
    }

    /// "123 456", "1234 5678": halves, as the iOS app shows them.
    static func grouped(_ code: String) -> String {
        guard code.count >= 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<middle]) + " " + String(code[middle...])
    }
}

/// How long a time-based code has left, as a ring that empties.
struct VaultMacCodeTimer: View {
    var state: OTPCodeTimerPeriodState
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let remaining = state.animationState.initialFraction(currentTime: context.date.timeIntervalSince1970)
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: remaining)
                    .stroke(remaining < 0.2 ? AnyShapeStyle(.red) : AnyShapeStyle(.tint), lineWidth: 2)
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}
