import Combine
import CryptoEngine
import Foundation
import VaultCore

/// Renders the code to a visible state for the given `code`.
public protocol OTPCodePublisher {
    @MainActor func renderedCodePublisher() -> AnyPublisher<String, any Error>
}

// MARK: - Mock

public final class OTPCodePublisherMock: OTPCodePublisher {
    public init() {}
    public let subject = PassthroughSubject<String, any Error>()
    public func renderedCodePublisher() -> AnyPublisher<String, any Error> {
        subject.eraseToAnyPublisher()
    }
}

// MARK: - Impl

public final class TOTPCodePublisher: OTPCodePublisher {
    private let timer: any OTPCodeTimerUpdater
    private let totpGenerator: TOTPGenerator

    public init(timer: any OTPCodeTimerUpdater, totpGenerator: TOTPGenerator) {
        self.timer = timer
        self.totpGenerator = totpGenerator
    }

    @MainActor
    public func renderedCodePublisher() -> AnyPublisher<String, any Error> {
        codeValuePublisher()
            .digitsRenderer(digits: totpGenerator.digits)
    }

    @MainActor
    private func codeValuePublisher() -> AnyPublisher<BigUInt, any Error> {
        let generator = totpGenerator
        return timer.timerUpdatedPublisher
            .setFailureType(to: (any Error).self)
            .tryMap { state in
                try generator.code(epochSeconds: UInt64(state.startTime))
            }
            .eraseToAnyPublisher()
    }
}

public final class HOTPCodePublisher: OTPCodePublisher {
    private let hotpGenerator: HOTPGenerator
    private let counterSubject: PassthroughSubject<UInt64, Never>

    public init(hotpGenerator: HOTPGenerator) {
        self.hotpGenerator = hotpGenerator
        counterSubject = PassthroughSubject()
    }

    /// Update the current value of the counter.
    @MainActor
    public func set(counter: UInt64) {
        counterSubject.send(counter)
    }

    public func renderedCodePublisher() -> AnyPublisher<String, any Error> {
        codeValuePublisher()
            .digitsRenderer(digits: hotpGenerator.digits)
    }

    private func codeValuePublisher() -> AnyPublisher<BigUInt, any Error> {
        let generator = hotpGenerator
        return counterSubject
            .setFailureType(to: (any Error).self)
            .tryMap { counterValue in
                try generator.code(counter: counterValue)
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Next code

/// Renders the code after the current one while it's due to show, and publishes `nil` the rest of the time.
public protocol OTPNextCodePublisher {
    @MainActor func renderedNextCodePublisher() -> AnyPublisher<String?, Never>
}

public final class OTPNextCodePublisherMock: OTPNextCodePublisher {
    public init() {}
    public let subject = PassthroughSubject<String?, Never>()
    public func renderedNextCodePublisher() -> AnyPublisher<String?, Never> {
        subject.eraseToAnyPublisher()
    }
}

/// The time-based code of the period after the current one, while `window` is open.
public final class TOTPNextCodePublisher: OTPNextCodePublisher {
    private let window: TOTPNextCodeWindow
    private let totpGenerator: TOTPGenerator

    public init(window: TOTPNextCodeWindow, totpGenerator: TOTPGenerator) {
        self.window = window
        self.totpGenerator = totpGenerator
    }

    @MainActor
    public func renderedNextCodePublisher() -> AnyPublisher<String?, Never> {
        let generator = totpGenerator
        return window.openPeriodPublisher
            .map { openPeriod in
                // The next period starts as this one ends.
                guard let openPeriod, let code = try? generator.code(epochSeconds: UInt64(openPeriod.endTime)) else {
                    return nil
                }
                return OTPCodeRenderer().render(code: code, digits: generator.digits)
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Helpers

extension Publisher where Output == BigUInt {
    func digitsRenderer(digits: UInt16) -> AnyPublisher<String, Failure> {
        map { code in
            OTPCodeRenderer().render(code: code, digits: digits)
        }
        .eraseToAnyPublisher()
    }
}
