import Combine
import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultFeed

@MainActor
struct OTPCodePreviewViewModelTests {
    @Test
    func code_updatesWithCodes() async throws {
        let (codePublisher, sut) = makeSUT()

        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send("hello")
        }
        #expect(sut.code == .visible("hello"))

        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send("world")
        }
        #expect(sut.code == .visible("world"))
    }

    @Test
    func code_lockedUpdatesWithObfuscatedCodes() async throws {
        let (codePublisher, sut) = makeSUT(isLocked: true)

        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send("hello")
        }
        #expect(sut.code == .locked(code: "hello"))

        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send("world")
        }
        #expect(sut.code == .locked(code: "world"))
    }

    @Test
    func code_goesToNoMoreCodesWhenFinished() async throws {
        let (codePublisher, sut) = makeSUT()

        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send("hi")
        }
        #expect(sut.code == .visible("hi"))

        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send(completion: .finished)
        }
        #expect(sut.code == .finished)
    }

    @Test
    func code_goesToErrorWhenErrors() async throws {
        let (codePublisher, sut) = makeSUT()

        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send(completion: .failure(TestError()))
        }

        guard case .error = sut.code else {
            Issue.record("Expected .error but got \(sut.code)")
            return
        }
    }

    @Test
    func update_setsCodeToVisible() {
        let (_, sut) = makeSUT()

        sut.update(.visible("123456"))

        #expect(sut.code == .visible("123456"))
    }

    @Test
    func update_obfuscatesForPrivacy() {
        let (_, sut) = makeSUT()

        sut.update(.visible("123456"))
        sut.update(.obfuscated(.privacy))

        #expect(sut.code == .obfuscated(.privacy))
    }

    @Test
    func updateRemovePrivacyObfuscation_removesPreviousPrivacyObfuscation() {
        let (_, sut) = makeSUT()

        sut.update(.visible("456"))
        sut.update(.obfuscated(.privacy))
        sut.updateRemovePrivacyObfuscation()

        #expect(sut.code == .visible("456"))
    }

    @Test
    func updateRemovePrivacyObfuscation_hasNoEffectForNonPrivacyObfuscation() {
        let states: [OTPCodeState] = [
            .obfuscated(.expiry),
            .error(.init(userTitle: "", debugDescription: ""), digits: 1),
            .finished,
            .notReady,
            .visible("111"),
            .locked(code: "1234"),
        ]
        for state in states {
            let (_, sut) = makeSUT()
            sut.update(.visible("456"))
            sut.update(state)
            sut.updateRemovePrivacyObfuscation()

            #expect(sut.code == state, "\(state) should be the current state")
        }
    }

    @Test
    func visibleIssuer_isPlaceholderIfIssuerEmpty() {
        let (_, sut) = makeSUT(issuer: "")

        #expect(sut.visibleIssuer == "Unnamed")
    }

    @Test
    func visibleIssuer_isIssuerIfNotEmpty() {
        let (_, sut) = makeSUT(issuer: "my issuer")

        #expect(sut.visibleIssuer == "my issuer")
    }

    @Test
    func pasteboardCopyText_isVisibleCode() {
        let (_, sut) = makeSUT()
        sut.update(.visible("1234"))

        let expected = VaultTextCopyAction(text: "1234", requiresAuthenticationToCopy: false, contentType: .otp)
        #expect(sut.pasteboardCopyText == expected)
    }

    @Test
    func pasteboardCopyText_isLockedCode() {
        let (_, sut) = makeSUT()
        sut.update(.locked(code: "4567"))

        let expected = VaultTextCopyAction(text: "4567", requiresAuthenticationToCopy: true, contentType: .otp)
        #expect(sut.pasteboardCopyText == expected)
    }

    @Test
    func pasteboardCopyText_isNil() {
        let nilCases: [OTPCodeState] = [
            .notReady,
            .finished,
            .error(.init(userTitle: "", debugDescription: ""), digits: 1),
            .obfuscated(.privacy),
            .obfuscated(.expiry),
        ]
        for nilCase in nilCases {
            let (_, sut) = makeSUT()
            sut.update(nilCase)

            #expect(sut.pasteboardCopyText == nil)
        }
    }

    // MARK: - Next code

    @Test
    func nextCode_isNilWithoutANextCodePublisher() async throws {
        let (codePublisher, sut) = makeSUT()

        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send("123456")
        }

        #expect(sut.nextCode == nil)
    }

    @Test
    func nextCode_followsTheNextCodeWhileTheCodeIsVisible() async throws {
        let (codePublisher, nextCodePublisher, sut) = makeSUTWithNextCode()
        try await sut.waitForChange(to: \.code) {
            codePublisher.subject.send("123456")
        }

        try await sut.waitForChange(to: \.nextCode) {
            nextCodePublisher.subject.send("654321")
        }
        #expect(sut.nextCode == "654321")

        try await sut.waitForChange(to: \.nextCode) {
            nextCodePublisher.subject.send(nil)
        }
        #expect(sut.nextCode == nil)
    }

    @Test
    func nextCode_isHiddenWheneverTheCodeIsHidden() async throws {
        let hiddenStates: [OTPCodeState] = [
            .locked(code: "123456"),
            .obfuscated(.privacy),
            .obfuscated(.expiry),
            .notReady,
            .finished,
            .error(.init(userTitle: "", debugDescription: ""), digits: 6),
        ]
        for hiddenState in hiddenStates {
            let (_, nextCodePublisher, sut) = makeSUTWithNextCode()
            sut.update(.visible("123456"))
            try await sut.waitForChange(to: \.nextCode) {
                nextCodePublisher.subject.send("654321")
            }

            sut.update(hiddenState)

            #expect(sut.nextCode == nil, "\(hiddenState) hides the next code")
        }
    }

    @Test
    func nextCode_returnsOnceThePrivacyObfuscationIsRemoved() async throws {
        let (_, nextCodePublisher, sut) = makeSUTWithNextCode()
        sut.update(.visible("123456"))
        try await sut.waitForChange(to: \.nextCode) {
            nextCodePublisher.subject.send("654321")
        }

        sut.update(.obfuscated(.privacy))
        #expect(sut.nextCode == nil)
        sut.updateRemovePrivacyObfuscation()

        #expect(sut.nextCode == "654321")
    }

    @Test
    func pasteboardCopyText_isTheCurrentCodeWhileTheNextCodeShows() async throws {
        let (_, nextCodePublisher, sut) = makeSUTWithNextCode()
        sut.update(.visible("123456"))
        try await sut.waitForChange(to: \.nextCode) {
            nextCodePublisher.subject.send("654321")
        }

        let expected = VaultTextCopyAction(text: "123456", requiresAuthenticationToCopy: false, contentType: .otp)
        #expect(sut.pasteboardCopyText == expected)
    }

    @Test
    func nextCode_isTheFixedNextCode() {
        let sut = OTPCodePreviewViewModel(
            accountName: "any",
            issuer: "any",
            color: .default,
            isLocked: false,
            fixedCodeState: .visible("123456"),
            fixedNextCode: "654321",
        )

        #expect(sut.nextCode == "654321")
    }

    // MARK: - Helpers

    private func makeSUT(
        issuer: String = "any",
        isLocked: Bool = false,
    ) -> (OTPCodePublisherMock, OTPCodePreviewViewModel) {
        let codePublisher = OTPCodePublisherMock()
        let viewModel = OTPCodePreviewViewModel(
            accountName: "any",
            issuer: issuer,
            color: .default,
            isLocked: isLocked,
            codePublisher: codePublisher,
        )
        return (codePublisher, viewModel)
    }

    private func makeSUTWithNextCode() -> (OTPCodePublisherMock, OTPNextCodePublisherMock, OTPCodePreviewViewModel) {
        let codePublisher = OTPCodePublisherMock()
        let nextCodePublisher = OTPNextCodePublisherMock()
        let viewModel = OTPCodePreviewViewModel(
            accountName: "any",
            issuer: "any",
            color: .default,
            isLocked: false,
            codePublisher: codePublisher,
            nextCodePublisher: nextCodePublisher,
        )
        return (codePublisher, nextCodePublisher, viewModel)
    }
}
