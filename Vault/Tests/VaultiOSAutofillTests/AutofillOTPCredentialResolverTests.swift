import Foundation
import FoundationExtensions
import Testing
import VaultCore
import VaultFeed
@testable import VaultiOSAutofill

@MainActor
struct AutofillOTPCredentialResolverTests {
    @Test
    func resolve_nilRecordIdentifier_returnsNotFound() async {
        let sut = makeSUT()

        let outcome = await sut.resolve(recordIdentifier: nil)

        #expect(outcome == .notFound)
    }

    @Test
    func resolve_malformedRecordIdentifier_returnsNotFound() async {
        let sut = makeSUT()

        let outcome = await sut.resolve(recordIdentifier: "not-a-uuid")

        #expect(outcome == .notFound)
    }

    @Test
    func resolve_unknownItemID_returnsNotFound() async {
        let sut = makeSUT(items: [makeOTPItem(type: .totp())])

        let outcome = await sut.resolve(recordIdentifier: UUID().uuidString)

        #expect(outcome == .notFound)
    }

    @Test
    func resolve_nonOTPItem_returnsNotFound() async {
        let note = anyVaultItem()
        let sut = makeSUT(items: [note])

        let outcome = await sut.resolve(recordIdentifier: note.id.rawValue.uuidString)

        #expect(outcome == .notFound)
    }

    @Test
    func resolve_authRequiredItem_returnsUserInteractionRequired() async {
        // The security gate: an item whose copy action demands device
        // authentication must never be served without interaction.
        let item = makeOTPItem(type: .totp())
        let sut = makeSUT(items: [item], requiresAuthenticationToCopy: true)

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .userInteractionRequired)
    }

    @Test
    func resolve_hotpItem_returnsUserInteractionRequired() async {
        // HOTP counters must not increment without UI.
        let item = makeOTPItem(type: .hotp())
        let sut = makeSUT(items: [item])

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .userInteractionRequired)
    }

    @Test
    func resolve_totpItem_returnsCodeRenderedForClockEpoch() async throws {
        let code = makeTOTPCode(period: 30)
        let item = VaultItem(metadata: anyVaultItemMetadata(), item: .otpCode(code))
        let clock = EpochClockMock(currentTime: 1_234_567_890)
        let sut = makeSUT(items: [item], clock: clock)

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        let expected = try TOTPAuthCode(period: 30, data: code.data)
            .renderCode(epochSeconds: 1_234_567_890)
        #expect(outcome == .code(expected))
    }

    @Test
    func resolve_retrievalError_returnsFailure() async {
        struct RetrievalError: Error {}
        let sut = makeSUT(retrieveItems: { throw RetrievalError() })

        let outcome = await sut.resolve(recordIdentifier: UUID().uuidString)

        #expect(outcome == .failure)
    }
}

// MARK: - Helpers

extension AutofillOTPCredentialResolverTests {
    private func makeSUT(
        items: [VaultItem] = [],
        requiresAuthenticationToCopy: Bool = false,
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
    ) -> AutofillOTPCredentialResolver {
        makeSUT(
            retrieveItems: { .init(items: items) },
            requiresAuthenticationToCopy: requiresAuthenticationToCopy,
            clock: clock,
        )
    }

    private func makeSUT(
        retrieveItems: @escaping () async throws -> VaultRetrievalResult<VaultItem>,
        requiresAuthenticationToCopy: Bool = false,
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
    ) -> AutofillOTPCredentialResolver {
        AutofillOTPCredentialResolver(
            retrieveItems: retrieveItems,
            copyActionHandler: CopyActionHandlerStub(requiresAuthenticationToCopy: requiresAuthenticationToCopy),
            clock: clock,
        )
    }

    private func makeOTPItem(type: OTPAuthType) -> VaultItem {
        VaultItem(
            metadata: anyVaultItemMetadata(),
            item: .otpCode(OTPAuthCode(
                type: type,
                data: makeOTPData(),
            )),
        )
    }

    private func makeTOTPCode(period: UInt64) -> OTPAuthCode {
        OTPAuthCode(type: .totp(period: period), data: makeOTPData())
    }

    private func makeOTPData() -> OTPAuthCodeData {
        OTPAuthCodeData(
            secret: .init(data: Data.random(count: 50), format: .base32),
            accountName: "Some Account",
        )
    }

    private struct CopyActionHandlerStub: VaultItemCopyActionHandler {
        let requiresAuthenticationToCopy: Bool

        func textToCopyForVaultItem(id _: Identifier<VaultItem>) -> VaultTextCopyAction? {
            VaultTextCopyAction(
                text: "123456",
                requiresAuthenticationToCopy: requiresAuthenticationToCopy,
                contentType: .otp,
            )
        }
    }
}
