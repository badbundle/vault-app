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

    /// A locked code is never served without the extension's UI, whatever the copy handler has cached. In the
    /// QuickType process it has cached nothing, as no preview is ever drawn there.
    @Test(arguments: [nil, CachedCopyAction.notRequiringAuthentication])
    func resolve_lockedItem_returnsUserInteractionRequired(cached: CachedCopyAction?) async {
        let item = makeOTPItem(type: .totp(), lockState: .lockedWithNativeSecurity)
        let sut = makeSUT(items: [item], cached: cached)

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .userInteractionRequired)
    }

    @Test
    func resolve_lockedHOTPItem_returnsUserInteractionRequired() async {
        let item = makeOTPItem(type: .hotp(), lockState: .lockedWithNativeSecurity)
        let sut = makeSUT(items: [item])

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .userInteractionRequired)
    }

    @Test
    func resolve_authRequiredCopyAction_returnsUserInteractionRequired() async {
        // An item whose copy action demands device authentication must never be served without interaction either.
        let item = makeOTPItem(type: .totp())
        let sut = makeSUT(items: [item], cached: .requiringAuthentication)

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .userInteractionRequired)
    }

    /// An unlocked code is served with nothing cached, as in the QuickType process.
    @Test
    func resolve_unlockedTOTPItemWithNothingCached_returnsTheCode() async {
        let item = makeOTPItem(type: .totp())
        let sut = makeSUT(items: [item], cached: nil)

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        guard case .code = outcome else {
            Issue.record("Expected a code, got \(outcome)")
            return
        }
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

    /// A code is rendered with its own period. At 120 seconds, a 60 second code is the RFC 4226 value for counter 2,
    /// and a 30 second code the value for counter 4.
    @Test(arguments: [(60, "359152"), (30, "338314")] as [(UInt64, String)])
    func resolve_totpItem_usesTheCodesPeriod(period: UInt64, expected: String) async {
        let code = OTPAuthCode(
            type: .totp(period: period),
            data: .init(secret: .init(data: Data("12345678901234567890".utf8), format: .base32), accountName: "any"),
        )
        let item = VaultItem(metadata: anyVaultItemMetadata(), item: .otpCode(code))
        let sut = makeSUT(items: [item], clock: EpochClockMock(currentTime: 120))

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .code(expected))
    }

    @Test
    func resolve_zeroPeriod_returnsFailure() async {
        let item = VaultItem(metadata: anyVaultItemMetadata(), item: .otpCode(makeTOTPCode(period: 0)))
        let sut = makeSUT(items: [item])

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .failure)
    }

    @Test
    func resolve_retrievalError_returnsFailure() async {
        struct RetrievalError: Error {}
        let sut = makeSUT(retrieveItems: { throw RetrievalError() })

        let outcome = await sut.resolve(recordIdentifier: UUID().uuidString)

        #expect(outcome == .failure)
    }

    @Test
    func resolve_appLockOn_returnsUserInteractionRequiredWithoutReadingTheVault() async {
        // The app lock's gate: with it on, no code is served until the user
        // has authenticated in the extension's UI.
        let item = VaultItem(metadata: anyVaultItemMetadata(), item: .otpCode(makeTOTPCode(period: 30)))
        var retrieveCount = 0
        let sut = makeSUT(
            retrieveItems: {
                retrieveCount += 1
                return .init(items: [item])
            },
            isAppLockEnabled: true,
        )

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .userInteractionRequired)
        #expect(retrieveCount == 0)
    }

    /// QuickType never serves a code while only the App Lock Password opens the vault: it needs the password, in the
    /// extension's UI.
    @Test
    func resolve_passwordNeeded_returnsUserInteractionRequiredWithoutReadingTheVault() async {
        let item = VaultItem(metadata: anyVaultItemMetadata(), item: .otpCode(makeTOTPCode(period: 30)))
        var retrieveCount = 0
        let sut = makeSUT(
            retrieveItems: {
                retrieveCount += 1
                return .init(items: [item])
            },
            accessMode: .password,
        )

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        #expect(outcome == .userInteractionRequired)
        #expect(retrieveCount == 0)
    }
}

extension AutofillOTPCredentialResolverTests {
    /// With the password off, the device key opens the vault and QuickType serves codes as it does for a plain vault.
    @Test
    func resolve_passwordOff_servesTheCode() async throws {
        let item = VaultItem(metadata: anyVaultItemMetadata(), item: .otpCode(makeTOTPCode(period: 30)))
        let sut = makeSUT(retrieveItems: { .init(items: [item]) }, accessMode: .deviceKey)

        let outcome = await sut.resolve(recordIdentifier: item.id.rawValue.uuidString)

        guard case .code = outcome else {
            Issue.record("Expected a code, got \(outcome)")
            return
        }
    }
}

// MARK: - Helpers

extension AutofillOTPCredentialResolverTests {
    private func makeSUT(
        items: [VaultItem] = [],
        cached: CachedCopyAction? = .notRequiringAuthentication,
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
    ) -> AutofillOTPCredentialResolver {
        makeSUT(
            retrieveItems: { .init(items: items) },
            cached: cached,
            clock: clock,
        )
    }

    private func makeSUT(
        retrieveItems: @escaping () async throws -> VaultRetrievalResult<VaultItem>,
        cached: CachedCopyAction? = .notRequiringAuthentication,
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
        isAppLockEnabled: Bool = false,
        accessMode: VaultAccessMode = .plain,
    ) -> AutofillOTPCredentialResolver {
        AutofillOTPCredentialResolver(
            retrieveItems: retrieveItems,
            copyActionHandler: CopyActionHandlerStub(cached: cached),
            clock: clock,
            isAppLockEnabled: isAppLockEnabled,
            accessMode: accessMode,
        )
    }

    private func makeOTPItem(type: OTPAuthType, lockState: VaultItemLockState = .notLocked) -> VaultItem {
        VaultItem(
            metadata: anyVaultItemMetadata(lockState: lockState),
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

    /// What the copy handler has cached for an item, from a preview drawn in this process.
    enum CachedCopyAction {
        case notRequiringAuthentication
        case requiringAuthentication
    }

    private struct CopyActionHandlerStub: VaultItemCopyActionHandler {
        /// `nil` for nothing cached, as in the QuickType process.
        let cached: CachedCopyAction?

        func textToCopyForVaultItem(id _: Identifier<VaultItem>) -> VaultTextCopyAction? {
            guard let cached else { return nil }
            return VaultTextCopyAction(
                text: "123456",
                requiresAuthenticationToCopy: cached == .requiringAuthentication,
                contentType: .otp,
            )
        }
    }
}
