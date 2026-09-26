import Combine
import Foundation
import VaultCore

/// A preview of an OTP code.
@MainActor
@Observable
public final class OTPCodePreviewViewModel {
    public let accountName: String
    public let issuer: String
    public let color: VaultItemColor
    public let isLocked: Bool
    public private(set) var code: OTPCodeState = .notReady
    private var obfuscatedCode: OTPCodeState?
    private var upcomingCode: String?

    /// The code after the current one, near the end of the current one's countdown, to show beside it.
    ///
    /// Only while the current code itself shows: whatever hides that (the item's lock, privacy, expiry) hides this.
    public var nextCode: String? {
        code.isVisible ? upcomingCode : nil
    }

    public var visibleIssuer: String {
        if issuer.isNotEmpty {
            issuer
        } else {
            localized(key: "codeDetail.field.siteName.empty.title")
        }
    }

    private var cancellables = Set<AnyCancellable>()

    public init(
        accountName: String,
        issuer: String,
        color: VaultItemColor,
        isLocked: Bool,
        fixedCodeState: OTPCodeState,
        fixedNextCode: String? = nil,
    ) {
        self.accountName = accountName
        self.issuer = issuer
        self.color = color
        self.isLocked = isLocked
        code = fixedCodeState
        upcomingCode = fixedNextCode
    }

    /// - Parameter nextCodePublisher: The code after the current one while it's due to show, for a code that has one.
    public init(
        accountName: String,
        issuer: String,
        color: VaultItemColor,
        isLocked: Bool,
        codePublisher: some OTPCodePublisher,
        nextCodePublisher: (any OTPNextCodePublisher)? = nil,
    ) {
        self.accountName = accountName
        self.color = color
        self.issuer = issuer
        self.isLocked = isLocked
        codePublisher.renderedCodePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self else { return }
                switch completion {
                case .finished:
                    code = .finished
                case let .failure(error):
                    code = .error(
                        PresentationError(
                            userTitle: localized(key: "codePreview.codeGenerationError.title"),
                            userDescription: localized(key: "codePreview.codeGenerationError.description"),
                            debugDescription: error.localizedDescription,
                        ),
                        digits: 6,
                    )
                }
            } receiveValue: { [weak self] code in
                guard let self else { return }
                if isLocked {
                    self.code = .locked(code: code)
                } else {
                    self.code = .visible(code)
                }
            }
            .store(in: &cancellables)
        nextCodePublisher?.renderedNextCodePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nextCode in
                self?.upcomingCode = nextCode
            }
            .store(in: &cancellables)
    }

    public func update(_ newValue: OTPCodeState) {
        let oldValue = code
        if oldValue != .obfuscated(.privacy), newValue == .obfuscated(.privacy) {
            obfuscatedCode = oldValue
        }
        code = newValue
    }

    /// If the code was obfuscated for privacy, this removes the obfuscation and sets the code value to the value before
    /// it was obfuscated.
    ///
    /// Has no effect if the code was not hidden for a privacy.
    public func updateRemovePrivacyObfuscation() {
        if let obfuscatedCode, case .obfuscated(.privacy) = code {
            code = obfuscatedCode
        }
        obfuscatedCode = nil
    }

    public var pasteboardCopyText: VaultTextCopyAction? {
        switch code {
        case let .visible(code):
            VaultTextCopyAction(text: code, requiresAuthenticationToCopy: false, contentType: .otp)
        case let .locked(code):
            VaultTextCopyAction(text: code, requiresAuthenticationToCopy: true, contentType: .otp)
        case .notReady, .finished, .obfuscated, .error:
            nil
        }
    }
}
