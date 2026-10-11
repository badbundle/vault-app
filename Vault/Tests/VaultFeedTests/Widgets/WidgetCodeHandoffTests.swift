import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

/// The codes the unlocked Mac app hands its widgets (G98).
struct WidgetCodeHandoffTests {
    /// Partway through a 30-second period, so the first code started before `now`.
    private let now = Date(timeIntervalSince1970: 1_800_000_010)

    @Test
    func init_coversTheWindowWithEachPeriodsCode() throws {
        let code = anyOTPAuthCode(type: .totp(period: 30), issuerName: "Issuer")
        let item = uniqueVaultItem(item: .otpCode(code))

        let handoff = WidgetCodeHandoff(items: [item], now: now, window: 5 * 60)

        let handedOver = try #require(handoff.item(id: item.id.rawValue))
        let totp = TOTPAuthCode(period: 30, data: code.data)
        #expect(handoff.expiresAt == now.addingTimeInterval(5 * 60))
        #expect(handedOver.issuer == "Issuer")
        #expect(handedOver.digits == 6)
        // The period showing now, and every one that starts before the handoff expires.
        #expect(handedOver.codes.count == 11)
        #expect(handedOver.codes.first?.start == Date(timeIntervalSince1970: 1_800_000_000))
        for entry in handedOver.codes {
            #expect(entry.end == entry.start.addingTimeInterval(30))
            #expect(try entry.code == totp.renderCode(epochSeconds: UInt64(entry.start.timeIntervalSince1970)))
        }
        #expect(try #require(handedOver.codes.last).start < handoff.expiresAt)
    }

    @Test
    func init_usesEachCodesOwnPeriod() throws {
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .totp(period: 60))))

        let handoff = WidgetCodeHandoff(items: [item], now: now, window: 5 * 60)

        let codes = try #require(handoff.item(id: item.id.rawValue)).codes
        #expect(codes.count == 6)
        #expect(codes.allSatisfy { $0.end.timeIntervalSince($0.start) == 60 })
    }

    /// Never a secret: only the codes, the site, the account and the number of digits are handed over.
    @Test
    func encoded_neverHoldsTheSecret() throws {
        let code = anyOTPAuthCode(accountName: "someone@example.com", issuerName: "Issuer")
        let item = uniqueVaultItem(item: .otpCode(code))

        let encoded = try JSONEncoder().encode(WidgetCodeHandoff(items: [item], now: now))

        let secret = code.data.secret
        #expect(encoded.range(of: secret.data) == nil)
        #expect(encoded.range(of: Data(secret.base32EncodedString.utf8)) == nil)
        #expect(encoded.range(of: Data(secret.data.base64EncodedString().utf8)) == nil)
        #expect(String(bytes: encoded, encoding: .utf8)?.contains("someone@example.com") == true)
    }

    /// A widget never shows a locked or hidden code (G45), so none is handed over.
    @Test
    func init_leavesOutWhatWidgetsMayNotShow() {
        let items = [
            uniqueVaultItem(lockState: .lockedWithNativeSecurity),
            uniqueVaultItem(visibility: .onlySearch),
            uniqueVaultItem(searchableLevel: .onlyPassphrase),
            uniqueVaultItem(item: .secureNote(SecureNote(title: "t", contents: "c", format: .markdown))),
        ]

        let handoff = WidgetCodeHandoff(items: items, now: now)

        #expect(handoff.items.isEmpty)
    }

    /// A counter-based code stays usable until it's used, so it's never worked out ahead.
    @Test
    func init_leavesOutCounterBasedCodes() {
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .hotp(counter: 4))))

        let handoff = WidgetCodeHandoff(items: [item], now: now)

        #expect(handoff.items.isEmpty)
    }

    /// As in the widgets' settings on iOS, a code with a killphrase is like any other (MANIFESTO C5, G5).
    @Test
    func init_includesACodeWithAKillphrase() {
        let item = uniqueVaultItem(killphrase: "any-phrase")

        let handoff = WidgetCodeHandoff(items: [item], now: now)

        #expect(handoff.items.map(\.id) == [item.id.rawValue])
    }

    @Test
    func init_aVeryShortPeriod_stopsAtTheMostCodes() throws {
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .totp(period: 1))))

        let handoff = WidgetCodeHandoff(items: [item], now: now, window: 5 * 60)

        let codes = try #require(handoff.item(id: item.id.rawValue)).codes
        #expect(codes.count == WidgetCodeHandoff.maximumCodesPerItem)
    }

    @Test
    func code_isThePeriodsCodeUntilTheHandoffExpires() throws {
        let item = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(type: .totp(period: 30))))
        let handoff = WidgetCodeHandoff(items: [item], now: now, window: 60)
        let codes = try #require(handoff.item(id: item.id.rawValue)).codes

        #expect(handoff.code(itemID: item.id.rawValue, at: now) == codes[0].code)
        #expect(handoff.code(itemID: item.id.rawValue, at: now.addingTimeInterval(25)) == codes[1].code)
        #expect(handoff.code(itemID: item.id.rawValue, at: handoff.expiresAt) == nil)
        #expect(handoff.code(itemID: UUID(), at: now) == nil)
    }
}
